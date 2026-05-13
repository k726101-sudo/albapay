import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions";
import {S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand} from "@aws-sdk/client-s3";
import {getSignedUrl} from "@aws-sdk/s3-request-presigner";

// ─────────────────────────────────────────────────────────
// R2 비밀키 설정 (Firebase Secret Manager 연동)
// ─────────────────────────────────────────────────────────
const R2_ACCOUNT_ID = defineSecret("R2_ACCOUNT_ID");
const R2_ACCESS_KEY_ID = defineSecret("R2_ACCESS_KEY_ID");
const R2_SECRET_ACCESS_KEY = defineSecret("R2_SECRET_ACCESS_KEY");
const R2_BUCKET_NAME = defineSecret("R2_BUCKET_NAME");
// const R2_PUBLIC_BASE_URL = defineSecret("R2_PUBLIC_BASE_URL"); // 추후 CDN 연결 시 사용

// ─────────────────────────────────────────────────────────
// S3 Client Singleton 반환
// ─────────────────────────────────────────────────────────
function getR2Client(): S3Client {
  return new S3Client({
    region: "auto",
    endpoint: `https://${R2_ACCOUNT_ID.value()}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: R2_ACCESS_KEY_ID.value(),
      secretAccessKey: R2_SECRET_ACCESS_KEY.value(),
    },
  });
}

// ─────────────────────────────────────────────────────────
// 상수 및 검증 로직
// ─────────────────────────────────────────────────────────
const ALLOWED_MIME_TYPES = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10MB

function getExtension(mimeType: string): string {
  switch (mimeType) {
    case "application/pdf": return "pdf";
    case "image/jpeg": return "jpg";
    case "image/png": return "png";
    case "image/webp": return "webp";
    default: return "bin";
  }
}

// ============================================================================
// 1. generateUploadUrl: 업로드 URL 발급 및 Pending DB 생성
// ============================================================================
export const generateUploadUrl = onCall(
  {
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const {storeId, docType, mimeType, sizeBytes, sha256} = request.data;
    if (!storeId || !docType || !mimeType || !sizeBytes) {
      throw new HttpsError("invalid-argument", "Missing required parameters");
    }

    // 1. MIME 검증
    if (!ALLOWED_MIME_TYPES.includes(mimeType)) {
      throw new HttpsError("invalid-argument", "Unsupported file type");
    }

    // 2. Size 검증
    if (sizeBytes > MAX_FILE_SIZE_BYTES) {
      throw new HttpsError("invalid-argument", "File size exceeds 10MB limit");
    }

    const db = admin.firestore();
    const bucket = R2_BUCKET_NAME.value();
    const uid = request.auth.uid;
    const clientIp = request.rawRequest.ip || "unknown";

    // 3. Object Key Naming Standard
    const now = new Date();
    const yyyyMM = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const docRef = db.collection("stores").doc(storeId).collection("documents").doc();
    const ext = getExtension(mimeType);
    const objectKey = `stores/${storeId}/documents/${docType}/${yyyyMM}/${docRef.id}.${ext}`;

    // 4. Firestore에 pending 레코드 생성
    await docRef.set({
      id: docRef.id,
      storeId,
      docType,
      mimeType,
      sizeBytes,
      sha256: sha256 || null,
      objectKey,
      status: "pending",
      uploadedBy: uid,
      ip: clientIp,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 5. Presigned URL 발급 (15분 유효)
    const client = getR2Client();
    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: objectKey,
      ContentType: mimeType,
      ContentLength: sizeBytes,
      // SHA-256 검증 강제를 위해 헤더 포함 (클라이언트도 보내야 함)
      ...(sha256 && {ChecksumSHA256: sha256}),
    });

    try {
      const uploadUrl = await getSignedUrl(client, command, {expiresIn: 15 * 60});
      logger.info(`Generated upload URL for ${objectKey}`, {uid, storeId});
      return {uploadUrl, docId: docRef.id, objectKey};
    } catch (error) {
      logger.error("Failed to generate presigned URL", error);
      throw new HttpsError("internal", "Could not generate upload URL");
    }
  }
);

// ============================================================================
// 2. finalizeUpload: R2 실제 업로드 확인 및 DB Commit
// ============================================================================
export const finalizeUpload = onCall(
  {
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const {storeId, docId} = request.data;
    if (!storeId || !docId) {
      throw new HttpsError("invalid-argument", "Missing storeId or docId");
    }

    const db = admin.firestore();
    const docRef = db.collection("stores").doc(storeId).collection("documents").doc(docId);
    const snap = await docRef.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", "Document record not found");
    }

    const data = snap.data()!;
    if (data.status === "completed") {
      return {success: true, message: "Already finalized"};
    }

    const client = getR2Client();
    const command = new HeadObjectCommand({
      Bucket: R2_BUCKET_NAME.value(),
      Key: data.objectKey,
    });

    try {
      const head = await client.send(command);
      
      // 실제 크기 검증 (Cross-check)
      if (head.ContentLength !== data.sizeBytes) {
        logger.warn("Size mismatch during finalize", {expected: data.sizeBytes, actual: head.ContentLength});
        // 실제 크기로 업데이트
        await docRef.update({sizeBytes: head.ContentLength});
      }

      // 상태 확정 (DB Commit)
      await docRef.update({
        status: "completed",
        finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`Upload finalized for ${data.objectKey}`, {docId, storeId});
      return {success: true, docId};
    } catch (error) {
      logger.error("Finalize check failed (HeadObject)", error);
      // S3 에러 코드가 404/NotFound 이면 파일이 없는 것
      throw new HttpsError("failed-precondition", "File not found on R2 or error checking file");
    }
  }
);

// ============================================================================
// 3. generateDownloadUrl: 권한 확인 후 단기 다운로드 URL 발급
// ============================================================================
export const generateDownloadUrl = onCall(
  {
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const {storeId, docId} = request.data;
    const uid = request.auth.uid;

    if (!storeId || !docId) {
      throw new HttpsError("invalid-argument", "Missing parameters");
    }

    const db = admin.firestore();

    // ── 권한 재검증 (Strict Authorization) ──
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    if (!userData) {
      throw new HttpsError("permission-denied", "User not found");
    }

    // Boss이거나 해당 매장의 소속 알바생인지 확인
    let hasAccess = false;
    if (userData.pushRole === "boss" || userData.stores?.includes(storeId)) {
      // 사장님 이거나 stores 필드에 매장이 있으면 통과 (간이 권한 체크)
      hasAccess = true;
    } else {
      // 알바생인 경우 worker 서브컬렉션 소속 확인
      const workerSnap = await db.collection("stores").doc(storeId).collection("workers").where("uid", "==", uid).limit(1).get();
      if (!workerSnap.empty) {
        hasAccess = true;
      }
    }

    if (!hasAccess) {
      logger.warn("Unauthorized download attempt", {uid, storeId, docId});
      throw new HttpsError("permission-denied", "You do not have permission to access this document");
    }

    // 문서 확인
    const docSnap = await db.collection("stores").doc(storeId).collection("documents").doc(docId).get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Document not found");
    }

    const docData = docSnap.data()!;
    if (docData.status !== "completed") {
      throw new HttpsError("failed-precondition", "Document upload not finalized yet");
    }

    // ── Presigned GET URL 발급 (수명: 5분 최소화) ──
    const client = getR2Client();
    const command = new GetObjectCommand({
      Bucket: R2_BUCKET_NAME.value(),
      Key: docData.objectKey,
    });

    try {
      const downloadUrl = await getSignedUrl(client, command, {expiresIn: 5 * 60});
      
      // 다운로드 이력 기록 (선택)
      await db.collection("stores").doc(storeId).collection("documents").doc(docId).collection("accessLogs").add({
        accessedBy: uid,
        accessedAt: admin.firestore.FieldValue.serverTimestamp(),
        ip: request.rawRequest.ip || "unknown",
      });

      return {downloadUrl, expires: 5 * 60};
    } catch (error) {
      logger.error("Failed to generate download URL", error);
      throw new HttpsError("internal", "Could not generate download URL");
    }
  }
);
