"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateDownloadUrl = exports.finalizeUpload = exports.generateUploadUrl = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firebase_functions_1 = require("firebase-functions");
const client_s3_1 = require("@aws-sdk/client-s3");
const s3_request_presigner_1 = require("@aws-sdk/s3-request-presigner");
// ─────────────────────────────────────────────────────────
// R2 비밀키 설정 (Firebase Secret Manager 연동)
// ─────────────────────────────────────────────────────────
const R2_ACCOUNT_ID = (0, params_1.defineSecret)("R2_ACCOUNT_ID");
const R2_ACCESS_KEY_ID = (0, params_1.defineSecret)("R2_ACCESS_KEY_ID");
const R2_SECRET_ACCESS_KEY = (0, params_1.defineSecret)("R2_SECRET_ACCESS_KEY");
const R2_BUCKET_NAME = (0, params_1.defineSecret)("R2_BUCKET_NAME");
// const R2_PUBLIC_BASE_URL = defineSecret("R2_PUBLIC_BASE_URL"); // 추후 CDN 연결 시 사용
// ─────────────────────────────────────────────────────────
// S3 Client Singleton 반환
// ─────────────────────────────────────────────────────────
function getR2Client() {
    return new client_s3_1.S3Client({
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
function getExtension(mimeType) {
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
exports.generateUploadUrl = (0, https_1.onCall)({
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const { storeId, docType, mimeType, sizeBytes, sha256 } = request.data;
    if (!storeId || !docType || !mimeType || !sizeBytes) {
        throw new https_1.HttpsError("invalid-argument", "Missing required parameters");
    }
    // 1. MIME 검증
    if (!ALLOWED_MIME_TYPES.includes(mimeType)) {
        throw new https_1.HttpsError("invalid-argument", "Unsupported file type");
    }
    // 2. Size 검증
    if (sizeBytes > MAX_FILE_SIZE_BYTES) {
        throw new https_1.HttpsError("invalid-argument", "File size exceeds 10MB limit");
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
    const command = new client_s3_1.PutObjectCommand({
        Bucket: bucket,
        Key: objectKey,
        ContentType: mimeType,
        ContentLength: sizeBytes,
        // SHA-256 검증 강제를 위해 헤더 포함 (클라이언트도 보내야 함)
        ...(sha256 && { ChecksumSHA256: sha256 }),
    });
    try {
        const uploadUrl = await (0, s3_request_presigner_1.getSignedUrl)(client, command, { expiresIn: 15 * 60 });
        firebase_functions_1.logger.info(`Generated upload URL for ${objectKey}`, { uid, storeId });
        return { uploadUrl, docId: docRef.id, objectKey };
    }
    catch (error) {
        firebase_functions_1.logger.error("Failed to generate presigned URL", error);
        throw new https_1.HttpsError("internal", "Could not generate upload URL");
    }
});
// ============================================================================
// 2. finalizeUpload: R2 실제 업로드 확인 및 DB Commit
// ============================================================================
exports.finalizeUpload = (0, https_1.onCall)({
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const { storeId, docId } = request.data;
    if (!storeId || !docId) {
        throw new https_1.HttpsError("invalid-argument", "Missing storeId or docId");
    }
    const db = admin.firestore();
    const docRef = db.collection("stores").doc(storeId).collection("documents").doc(docId);
    const snap = await docRef.get();
    if (!snap.exists) {
        throw new https_1.HttpsError("not-found", "Document record not found");
    }
    const data = snap.data();
    if (data.status === "completed") {
        return { success: true, message: "Already finalized" };
    }
    const client = getR2Client();
    const command = new client_s3_1.HeadObjectCommand({
        Bucket: R2_BUCKET_NAME.value(),
        Key: data.objectKey,
    });
    try {
        const head = await client.send(command);
        // 실제 크기 검증 (Cross-check)
        if (head.ContentLength !== data.sizeBytes) {
            firebase_functions_1.logger.warn("Size mismatch during finalize", { expected: data.sizeBytes, actual: head.ContentLength });
            // 실제 크기로 업데이트
            await docRef.update({ sizeBytes: head.ContentLength });
        }
        // 상태 확정 (DB Commit)
        await docRef.update({
            status: "completed",
            finalizedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        firebase_functions_1.logger.info(`Upload finalized for ${data.objectKey}`, { docId, storeId });
        return { success: true, docId };
    }
    catch (error) {
        firebase_functions_1.logger.error("Finalize check failed (HeadObject)", error);
        // S3 에러 코드가 404/NotFound 이면 파일이 없는 것
        throw new https_1.HttpsError("failed-precondition", "File not found on R2 or error checking file");
    }
});
// ============================================================================
// 3. generateDownloadUrl: 권한 확인 후 단기 다운로드 URL 발급
// ============================================================================
exports.generateDownloadUrl = (0, https_1.onCall)({
    secrets: [R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME],
    region: "asia-northeast3",
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const { storeId, docId } = request.data;
    const uid = request.auth.uid;
    if (!storeId || !docId) {
        throw new https_1.HttpsError("invalid-argument", "Missing parameters");
    }
    const db = admin.firestore();
    // ── 권한 재검증 (Strict Authorization) ──
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    if (!userData) {
        throw new https_1.HttpsError("permission-denied", "User not found");
    }
    // Boss이거나 해당 매장의 소속 알바생인지 확인
    let hasAccess = false;
    if (userData.pushRole === "boss" || userData.stores?.includes(storeId)) {
        // 사장님 이거나 stores 필드에 매장이 있으면 통과 (간이 권한 체크)
        hasAccess = true;
    }
    else {
        // 알바생인 경우 worker 서브컬렉션 소속 확인
        const workerSnap = await db.collection("stores").doc(storeId).collection("workers").where("uid", "==", uid).limit(1).get();
        if (!workerSnap.empty) {
            hasAccess = true;
        }
    }
    if (!hasAccess) {
        firebase_functions_1.logger.warn("Unauthorized download attempt", { uid, storeId, docId });
        throw new https_1.HttpsError("permission-denied", "You do not have permission to access this document");
    }
    // 문서 확인
    const docSnap = await db.collection("stores").doc(storeId).collection("documents").doc(docId).get();
    if (!docSnap.exists) {
        throw new https_1.HttpsError("not-found", "Document not found");
    }
    const docData = docSnap.data();
    if (docData.status !== "completed") {
        throw new https_1.HttpsError("failed-precondition", "Document upload not finalized yet");
    }
    // ── Presigned GET URL 발급 (수명: 5분 최소화) ──
    const client = getR2Client();
    const command = new client_s3_1.GetObjectCommand({
        Bucket: R2_BUCKET_NAME.value(),
        Key: docData.objectKey,
    });
    try {
        const downloadUrl = await (0, s3_request_presigner_1.getSignedUrl)(client, command, { expiresIn: 5 * 60 });
        // 다운로드 이력 기록 (선택)
        await db.collection("stores").doc(storeId).collection("documents").doc(docId).collection("accessLogs").add({
            accessedBy: uid,
            accessedAt: admin.firestore.FieldValue.serverTimestamp(),
            ip: request.rawRequest.ip || "unknown",
        });
        return { downloadUrl, expires: 5 * 60 };
    }
    catch (error) {
        firebase_functions_1.logger.error("Failed to generate download URL", error);
        throw new https_1.HttpsError("internal", "Could not generate download URL");
    }
});
