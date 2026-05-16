import * as admin from "firebase-admin";
import express from "express";
import {onDocumentCreated, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onRequest, onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";

admin.initializeApp();

/** Android `sign_in_with_apple`: Apple `form_post` → intent:// 로 앱에 code / id_token 전달 */
const ANDROID_PACKAGE_ID = "com.standard.albapay";

const appleBridgeApp = express();
appleBridgeApp.use(express.urlencoded({extended: true}));

appleBridgeApp.get("/", (_req, res) => {
  res
    .status(200)
    .type("text/plain")
    .send(
      "Apple Sign-In Android bridge. POST only. Deploy 후 이 HTTPS URL을 Apple Services ID Return URLs에 넣으세요.",
    );
});

appleBridgeApp.post("/", (req, res) => {
  const raw = req.body as Record<string, string | undefined>;
  const code = raw?.code ?? "";
  const id_token = raw?.id_token ?? "";
  const state = raw?.state ?? "";
  const user = raw?.user;

  if (!code) {
    logger.error("appleSignInAndroidBridge: missing code", {
      rawKeys: raw ? Object.keys(raw) : [],
    });
    res.status(400).send("missing code");
    return;
  }

  const params = new URLSearchParams();
  params.set("code", String(code));
  if (id_token) params.set("id_token", String(id_token));
  if (state) params.set("state", String(state));
  if (user) params.set("user", String(user));

  const qs = params.toString();
  const intent = `intent://callback?${qs}#Intent;package=${ANDROID_PACKAGE_ID};scheme=signinwithapple;end`;
  res.redirect(302, intent);
});

export const appleSignInAndroidBridge = onRequest(
  {
    region: "asia-northeast3",
    cors: false,
    invoker: "public",
  },
  appleBridgeApp,
);

type SubstitutionNotification = {
  type?: string;
  title?: string;
  message?: string;
  storeId?: string;
  proposerName?: string;
  proposerWeeklyPlannedHours?: number;
  over15Hours?: boolean;
  substitutionId?: string;
};

export const sendSubstitutionPush = onDocumentCreated(
  "stores/{storeId}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data() as SubstitutionNotification | undefined;
    if (!data || data.type != "substitution_request") return;

    const storeId = data.storeId ?? event.params.storeId;
    if (!storeId) return;

    const title = data.title ?? "대근 신청 도착";
    const body =
      data.message ??
      `${data.proposerName ?? "대근자"} 신청 · 주간 ${(
        data.proposerWeeklyPlannedHours ?? 0
      ).toFixed(1)}h · 15시간 초과: ${data.over15Hours ? "예" : "아니오"}`;

    const topic = `store_${storeId}_boss`;
    const payload: admin.messaging.Message = {
      topic,
      notification: {
        title,
        body,
      },
      data: {
        type: "substitution_request",
        substitutionId: data.substitutionId ?? "",
        storeId,
        proposerName: data.proposerName ?? "",
        proposerWeeklyPlannedHours: String(data.proposerWeeklyPlannedHours ?? ""),
        over15Hours: String(data.over15Hours ?? false),
      },
    };

    try {
      await admin.messaging().send(payload);
      logger.info("Substitution push sent", {topic, storeId});
    } catch (error) {
      logger.error("Failed to send substitution push", error);
    }
  },
);

/**
 * 데모 모드(체험하기)로 생성된 가짜 데이터 및 매장을 매일 새벽 3시에 일괄 정리하는 크론잡
 */
export const cleanupDemoSandbox = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "Asia/Seoul",
  },
  async () => {
    const db = admin.firestore();
    const batchSize = 500;

    try {
      // 1. isDemo: true 태그가 달린 가상 매장들을 가져옵니다.
      const demoStoresSnap = await db.collection("stores").where("isDemo", "==", true).get();
      if (demoStoresSnap.empty) {
        logger.info("No demo stores to clean up.");
        return;
      }

      logger.info(`Found ${demoStoresSnap.size} demo stores to delete.`);

      // 각 매장에 대해 연관된 데이터를 삭제합니다.
      for (const storeDoc of demoStoresSnap.docs) {
        const storeId = storeDoc.id;
        const ownerId = storeDoc.data().ownerId;

        // 2. 해당 매장과 연관된 출퇴근(attendance) 기록 강제 삭제 (최상위 컬렉션)
        const attendanceSnap = await db.collection("attendance").where("storeId", "==", storeId).get();
        if (!attendanceSnap.empty) {
          let batch = db.batch();
          let count = 0;
          for (const attDoc of attendanceSnap.docs) {
            batch.delete(attDoc.ref);
            count++;
            if (count === batchSize) {
              await batch.commit();
              batch = db.batch();
              count = 0;
            }
          }
          if (count > 0) {
            await batch.commit();
          }
          logger.info(`Deleted ${attendanceSnap.size} attendance records for demo store ${storeId}`);
        }

        // 3. 매장에 소속된 가상 사장님(users) 계정 데이터 삭제
        if (ownerId) {
          try {
            await db.collection("users").doc(ownerId).delete();
            // Firebase Auth 익명 유저 삭제 (선택적)
            await admin.auth().deleteUser(ownerId).catch(() => {
              // 이미 토큰 만료로 삭제되었거나 에러 난 경우 무시
            });
          } catch (e) {
            logger.warn(`Failed to delete demo user ${ownerId}`, e);
          }
        }

        // 4. 매장 문서 및 그 하위의 모든 컬렉션(workers, rosterDays 등) 재귀적 영구 삭제
        await db.recursiveDelete(storeDoc.ref);
        logger.info(`Successfully wiped out demo store data: ${storeId}`);
      }

      logger.info("Demo sandbox cleanup completed successfully.");
    } catch (error) {
      logger.error("Error cleaning up demo sandboxes", error);
    }
  }
);

/**
 * 인사팀(Cloud Function): 알바생 초대 수락 (안전한 온보딩)
 *
 * 보안 원칙:
 * - 전체 처리를 Firestore Transaction으로 묶어 원자적 실행
 * - invite 문서에 usedAt/usedByUid를 기록하여 재사용 방지
 * - worker 슬롯은 uid 비어있을 때만 연결 (같은 uid는 idempotent 성공)
 * - users/{uid}에 쓰는 필드는 서버에서 고정 (클라이언트 입력 무시)
 * - App Check 적용 (선택적 강제)
 *
 * 입력: { inviteCode: string, phone: string }
 * 출력: { storeId, workerId, workerName }
 */

export const acceptInvite = onCall(
  {
    region: "asia-northeast3",
    // App Check: 위변조된 클라이언트 요청 차단 (앱에 App Check 미적용 시 WARN만)
    enforceAppCheck: false, // true로 변경하면 App Check 미인증 요청 완전 차단
  },
  async (request) => {
    // ── 1. 인증 확인 ──
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const callerUid = request.auth.uid;

    // ── 2. 입력값 검증 ──
    const {inviteCode, phone} = request.data as {
      inviteCode?: string;
      phone?: string;
    };
    if (!inviteCode || typeof inviteCode !== "string" ||
        !phone || typeof phone !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "초대코드와 전화번호를 입력해 주세요.",
      );
    }

    // 서버 측 정규화 (클라이언트 값 신뢰하지 않음)
    const normalizedPhone = phone.replace(/[^0-9]/g, "").replace(/^82/, "0");
    const normalizedInvite = inviteCode.toLowerCase().startsWith("demo_")
      ? inviteCode
      : inviteCode.toUpperCase();

    if (normalizedPhone.length < 10 || normalizedPhone.length > 11) {
      throw new HttpsError("invalid-argument", "유효한 전화번호를 입력해 주세요.");
    }

    const db = admin.firestore();

    // ── 3. invite 문서 조회 (Transaction 밖에서 읽기 → storeId/workerId 확보) ──
    let inviteDocRef: admin.firestore.DocumentReference | null = null;
    let storeId: string | null = null;
    let workerIdHint: string | null = null;

    // 3-1. inviteCode 필드로 검색
    const inviteSnap = await db
      .collection("invites")
      .where("inviteCode", "==", normalizedInvite)
      .limit(1)
      .get();

    if (!inviteSnap.empty) {
      inviteDocRef = inviteSnap.docs[0].ref;
      const invData = inviteSnap.docs[0].data();
      storeId = invData.storeId?.toString().trim() || null;
      workerIdHint = invData.workerId?.toString().trim() || null;
    }

    // 3-2. 문서 ID가 초대코드인 경우 폴백
    if (!storeId) {
      const inviteDoc = await db.collection("invites").doc(normalizedInvite).get();
      if (inviteDoc.exists) {
        inviteDocRef = inviteDoc.ref;
        const invData = inviteDoc.data();
        storeId = invData?.storeId?.toString().trim() || null;
        workerIdHint = invData?.workerId?.toString().trim() || null;
      }
    }

    if (!storeId) {
      logger.warn("acceptInvite: invite not found", {callerUid, inviteCode: normalizedInvite});
      throw new HttpsError("not-found", "초대 링크가 유효하지 않습니다.");
    }

    // ── 4. worker 매칭 (workerIdHint 직접 조회 우선 → 쿼리 폴백) ──
    const workersRef = db.collection("stores").doc(storeId).collection("workers");
    let matchedWorkerId: string | null = null;
    let matchedWorkerName = "직원";

    // 4-1. invite 문서에 workerId가 있으면 직접 조회 (비용 절약)
    if (workerIdHint) {
      const wdoc = await workersRef.doc(workerIdHint).get();
      if (wdoc.exists) {
        const data = wdoc.data()!;
        const workerPhone = (data.phone || data.phoneNumber || "")
          .toString().replace(/[^0-9]/g, "").replace(/^82/, "0");
        if (workerPhone === normalizedPhone && data.status === "active") {
          matchedWorkerId = wdoc.id;
          matchedWorkerName = data.name?.toString() || "직원";
        }
      }
    }

    // 4-2. 직접 조회 실패 시 inviteCode 쿼리 폴백
    if (!matchedWorkerId) {
      let workerSnap = await workersRef
        .where("inviteCode", "==", normalizedInvite)
        .where("status", "==", "active")
        .limit(10)
        .get();

      if (workerSnap.empty) {
        workerSnap = await workersRef
          .where("invite_code", "==", normalizedInvite)
          .where("status", "==", "active")
          .limit(10)
          .get();
      }

      if (workerSnap.empty) {
        logger.warn("acceptInvite: no active worker for invite", {callerUid, storeId, inviteCode: normalizedInvite});
        throw new HttpsError("not-found", "초대코드가 유효하지 않습니다.");
      }

      for (const doc of workerSnap.docs) {
        const data = doc.data();
        const workerPhone = (data.phone || data.phoneNumber || "")
          .toString().replace(/[^0-9]/g, "").replace(/^82/, "0");
        if (workerPhone === normalizedPhone) {
          matchedWorkerId = doc.id;
          matchedWorkerName = data.name?.toString() || "직원";
          break;
        }
      }
    }

    if (!matchedWorkerId) {
      logger.warn("acceptInvite: phone mismatch", {callerUid, storeId, phone: normalizedPhone});
      throw new HttpsError("not-found", "사장님이 등록하지 않은 번호입니다. 매장에 문의하세요.");
    }

    // ── 5. Firestore Transaction: 원자적으로 검증 + 업데이트 ──
    const workerDocRef = workersRef.doc(matchedWorkerId);
    const userDocRef = db.collection("users").doc(callerUid);

    const result = await db.runTransaction(async (tx) => {
      // 5-1. worker 슬롯 재검증 (Transaction 내에서 최신 상태 확인)
      const workerDoc = await tx.get(workerDocRef);
      if (!workerDoc.exists) {
        throw new HttpsError("not-found", "직원 정보를 찾을 수 없습니다.");
      }
      const workerData = workerDoc.data()!;
      const existingUid = workerData.uid?.toString().trim() || "";

      // 하이재킹 방지: 다른 uid가 이미 점유 → 거부
      if (existingUid && existingUid !== callerUid) {
        throw new HttpsError(
          "already-exists",
          "이미 다른 사용자가 등록된 직원입니다. 매장에 문의하세요.",
        );
      }

      // 같은 uid가 이미 연결 → idempotent 성공 (재시도 안전)
      const isIdempotent = existingUid === callerUid;

      // 5-2. invite 재사용 방지 (invite 문서가 있는 경우)
      if (inviteDocRef) {
        const inviteDoc = await tx.get(inviteDocRef);
        if (inviteDoc.exists) {
          const invData = inviteDoc.data()!;
          const usedAt = invData.usedAt;
          const usedByUid = invData.usedByUid?.toString().trim();

          if (usedAt && usedByUid && usedByUid !== callerUid) {
            // 다른 사람이 이미 사용한 초대코드 → 거부
            throw new HttpsError(
              "already-exists",
              "이미 사용된 초대코드입니다. 매장에 새 초대코드를 요청해 주세요.",
            );
          }

          // invite 사용 기록 (같은 uid 재시도면 덮어쓰기 = idempotent)
          tx.update(inviteDocRef, {
            usedAt: admin.firestore.FieldValue.serverTimestamp(),
            usedByUid: callerUid,
          });
        }
      }

      // 5-3. users/{uid} 업데이트 (서버에서 고정된 필드만 기록)
      tx.set(userDocRef, {
        storeId,
        workerId: matchedWorkerId,
        workerName: matchedWorkerName,
        role: "worker",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      // 5-4. workers/{workerId} 에 uid 기록 (빈 슬롯이거나 idempotent 재시도)
      if (!isIdempotent) {
        tx.update(workerDocRef, {
          uid: callerUid,
          linkedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {storeId, workerId: matchedWorkerId, workerName: matchedWorkerName};
    });

    logger.info("acceptInvite success", {
      callerUid,
      storeId: result.storeId,
      workerId: result.workerId,
    });

    return result;
  },
);

export const sendSpecialClausePush = onDocumentUpdated(
  "stores/{storeId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    const wasFiveOrMore = before.isFiveOrMore === true;
    const isFiveOrMore = after.isFiveOrMore === true;
    const reason = after.fiveOrMoreDecisionReason || "";

    // 5인 미만에서 5인 이상으로 넘어갔으며, 특별 조항 때문인지 확인
    if (!wasFiveOrMore && isFiveOrMore && reason.includes("특별 조항")) {
      const storeId = event.params.storeId;
      const topic = `store_${storeId}_boss`;

      const payload: admin.messaging.Message = {
        topic,
        notification: {
          title: "🚨 5인 이상 사업장 자동 전환 안내",
          body: "평균 근로자는 5인 미만이지만, 5인 이상 출근한 날이 영업일의 절반을 초과하여 특별조항에 따라 5인 이상 사업장으로 전환되었습니다. 가산수당 기준 등을 꼭 확인하세요.",
        },
        data: {
          type: "special_clause_alert",
          storeId,
        },
      };

      try {
        await admin.messaging().send(payload);
        logger.info("Special clause push sent", { topic, storeId });
      } catch (error) {
        logger.error("Failed to send special clause push", error);
      }
    }
  }
);


export const sendDocumentStatusPush = onDocumentUpdated(
  "stores/{storeId}/documents/{docId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    const storeId = event.params.storeId;
    const workerId = after.staffId;
    
    if (!workerId) return;

    let docTypeStr = "문서";
    if (after.type === "laborContract") docTypeStr = "근로계약서";
    else if (after.type === "wageStatement") docTypeStr = "임금명세서";
    else if (after.type === "nightHolidayConsent") docTypeStr = "야간/휴일 근로 동의서";
    else if (after.type === "employeeRegistry") docTypeStr = "근로자명부";
    else if (after.type === "parentalConsent") docTypeStr = "친권자 동의서";
    else if (after.type === "pledge") docTypeStr = "서약서";

    // 1. 사장님 -> 알바 전송 (draft -> sent)
    if (before.status === "draft" && after.status === "sent") {
      const topic = `store_${storeId}_worker_${workerId}`;
      const payload: admin.messaging.Message = {
        topic,
        notification: {
          title: `📄 ${docTypeStr} 도착`,
          body: `사장님이 ${docTypeStr}를 보냈습니다. 확인해 주세요.`,
        },
        data: {
          type: "document_sent",
          storeId,
          docId: event.params.docId,
          docType: after.type ?? "",
        },
      };

      try {
        await admin.messaging().send(payload);
        logger.info("Document sent push successful", { topic, storeId });
      } catch (error) {
        logger.error("Failed to send document sent push", error);
      }
    }

    // 2. 알바 교부 완료 (sent -> delivered)
    if (before.status === "sent" && after.status === "delivered") {
      const topic = `store_${storeId}_boss`;
      const payload: admin.messaging.Message = {
        topic,
        notification: {
          title: `✅ ${docTypeStr} 교부 완료`,
          body: `알바생이 ${docTypeStr}를 성공적으로 교부받았습니다.`,
        },
        data: {
          type: "document_delivered",
          storeId,
          docId: event.params.docId,
          docType: after.type ?? "",
        },
      };

      try {
        await admin.messaging().send(payload);
        logger.info("Document delivered push successful", { topic, storeId });
      } catch (error) {
        logger.error("Failed to send document delivered push", error);
      }
    }
  }
);

// ============================================================================
// notificationQueue 자동 발송 (보건증·수습·서류 알림 등 Queue에 적재된 모든 알림 처리)
//
// 상태 머신: pending → processing → sent / failed
// 중복 방지: dedupeKey 기반 + status 검증
// 실패 재시도: retryCount + lastError 기록 (최대 3회)
// 토큰 정리: messaging/registration-token-not-registered 에러 시 자동 제거
// Audit Log: notificationLogs 컬렉션에 발송 이력 저장
// Rate Limit: 1분 20건 제한 (#1)
// Collapse Key: 같은 유형 알림 덮어쓰기 (#2)
// Batch Send: sendEachForMulticast 사용 (#3)
// In-App Fallback: FCM 실패 시 inAppAlerts 컬렉션에 뱃지 저장 (#7)
// ============================================================================

const MAX_RETRY = 3;
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1분
const RATE_LIMIT_MAX = 20; // 1분 최대 20건

function routeForType(type: string | undefined): string {
  switch (type) {
    case "healthCert":
    case "healthCertExpiring":
      return "/health";
    case "probationEnding":
      return "/staff";
    case "clock_in_pending":
    case "early_clock_out_pending":
    case "overtime_request":
    case "attendance_abnormal":
      return "/attendance";
    case "substitution_request":
      return "/substitution";
    case "document_sent":
    case "document_delivered":
      return "/documents";
    case "notice":
      return "/notices";
    default:
      return "/home";
  }
}

// Collapse Key 매핑 (#2) — 같은 유형의 알림은 디바이스에서 덮어씀
function collapseKeyForType(type: string | undefined, storeId: string | undefined): string {
  const base = storeId ?? "global";
  switch (type) {
    case "clock_in_pending":
    case "early_clock_out_pending":
    case "overtime_request":
    case "attendance_abnormal":
      return `${base}_attendance`;
    case "healthCert":
    case "healthCertExpiring":
      return `${base}_health`;
    case "notice":
      return `${base}_notice`;
    case "substitution_request":
      return `${base}_substitution`;
    default:
      return `${base}_general`;
  }
}

// Rate Limit 확인 (#1) — 1분간 같은 targetUid에 20건 이상 발송 방지
async function checkRateLimit(targetUid: string): Promise<boolean> {
  const cutoff = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);
  const recentSnap = await admin.firestore()
    .collection("notificationLogs")
    .where("targetUid", "==", targetUid)
    .where("sentAt", ">=", cutoff)
    .limit(RATE_LIMIT_MAX + 1)
    .get();
  return recentSnap.size < RATE_LIMIT_MAX;
}

// In-App Badge Fallback (#7) — FCM 실패 시 앱 내 알림 뱃지
async function writeInAppAlert(opts: {
  targetUid: string;
  storeId: string;
  type: string;
  title: string;
  message: string;
  route: string;
}) {
  await admin.firestore()
    .collection("users")
    .doc(opts.targetUid)
    .collection("inAppAlerts")
    .add({
      ...opts,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

export const processNotificationQueue = onDocumentCreated(
  {
    document: "notificationQueue/{docId}",
    region: "asia-northeast3",       // #5 서울 리전
    timeoutSeconds: 120,              // #6 timeout 설정
    memory: "256MiB",                 // #6 memory 설정
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const docRef = snap.ref;
    const status = data.status ?? "queued";

    // 이미 처리된 문서는 무시 (중복 방지)
    if (status !== "queued" && status !== "pending") return;

    // processing 상태로 즉시 전환 (동시 실행 방지)
    await docRef.update({
      status: "processing",
      processingAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const channel = data.channel as string | undefined;
    const storeId = data.storeId as string | undefined;
    const targetUid = data.targetUid as string | undefined;
    const message = data.message as string | undefined;
    const msgTitle = data.title as string | undefined;
    const type = data.type as string | undefined;
    const retryCount = (data.retryCount as number | undefined) ?? 0;
    const collapse = collapseKeyForType(type, storeId);

    try {
      if (channel === "pushBoss" && targetUid) {
        // Rate Limit 확인 (#1)
        const allowed = await checkRateLimit(targetUid);
        if (!allowed) {
          logger.warn("Rate limit exceeded", {targetUid, docId: event.params.docId});
          await docRef.update({status: "rate_limited", rateLimitedAt: admin.firestore.FieldValue.serverTimestamp()});
          return;
        }

        // ── 사장님 개인 푸시 (FCM Token 기반) ──
        const userSnap = await admin.firestore().collection("users").doc(targetUid).get();
        const userData = userSnap.data();
        const tokens: string[] = userData?.fcmTokens ?? [];

        if (tokens.length === 0 && storeId) {
          // 토큰이 없을 경우 Topic 폴백
          const topic = `store_${storeId}_boss`;
          await admin.messaging().send({
            topic,
            notification: {
              title: msgTitle ?? "알바급여정석 알림",
              body: message ?? "",
            },
            data: {
              type: type ?? "general",
              storeId: storeId ?? "",
              route: routeForType(type),
            },
            android: {collapseKey: collapse},   // #2 Collapse Key
            apns: {headers: {"apns-collapse-id": collapse}},
          });
        } else {
          // Batch 발송 (#3 sendEachForMulticast 활용)
          const batchResult = await admin.messaging().sendEachForMulticast({
            tokens,
            notification: {
              title: msgTitle ?? "알바급여정석 알림",
              body: message ?? "",
            },
            data: {
              type: type ?? "general",
              storeId: storeId ?? "",
              route: routeForType(type),
            },
            android: {collapseKey: collapse},   // #2 Collapse Key
            apns: {headers: {"apns-collapse-id": collapse}},
          });

          // 유효하지 않은 토큰 자동 정리
          const invalidTokens: string[] = [];
          batchResult.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const errCode = (resp.error as {code?: string})?.code ?? "";
              if (
                errCode === "messaging/registration-token-not-registered" ||
                errCode === "messaging/invalid-registration-token"
              ) {
                invalidTokens.push(tokens[idx]);
                logger.warn("Removing invalid FCM token", {token: tokens[idx].substring(0, 10), uid: targetUid});
              }
            }
          });
          if (invalidTokens.length > 0) {
            await admin.firestore().collection("users").doc(targetUid).update({
              fcmTokens: admin.firestore.FieldValue.arrayRemove(invalidTokens),
            });
          }

          // 전체 실패 시 in-app fallback (#7)
          if (batchResult.successCount === 0 && storeId) {
            await writeInAppAlert({
              targetUid,
              storeId,
              type: type ?? "general",
              title: msgTitle ?? "알바급여정석 알림",
              message: message ?? "",
              route: routeForType(type),
            });
            logger.warn("All FCM tokens failed, wrote in-app alert", {targetUid});
          }
        }
      } else if (channel === "pushStaff" && storeId) {
        // ── 알바생 Topic 푸시 ──
        const workerId = data.targetUid ?? data.targetStaffId;
        const topic = workerId
          ? `store_${storeId}_worker_${workerId}`
          : `store_${storeId}_workers`;
        await admin.messaging().send({
          topic,
          notification: {
            title: msgTitle ?? "알바급여정석 알림",
            body: message ?? "",
          },
          data: {
            type: type ?? "general",
            storeId,
            route: routeForType(type),
          },
          android: {collapseKey: collapse},   // #2
          apns: {headers: {"apns-collapse-id": collapse}},
        });
      }

      // ── 발송 성공 ──
      await docRef.update({
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Audit Log
      await admin.firestore().collection("notificationLogs").add({
        queueDocId: event.params.docId,
        channel,
        storeId: storeId ?? "",
        targetUid: targetUid ?? "",
        type: type ?? "",
        message: message ?? "",
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info("Notification sent", {docId: event.params.docId, channel, type});
    } catch (error: unknown) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error("Notification send failed", {docId: event.params.docId, error: errMsg, retryCount});

      if (retryCount < MAX_RETRY) {
        await docRef.update({
          status: "queued",
          retryCount: retryCount + 1,
          lastError: errMsg,
          lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.update({
          status: "failed",
          retryCount,
          lastError: errMsg,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await admin.firestore().collection("notificationLogs").add({
          queueDocId: event.params.docId,
          channel,
          storeId: storeId ?? "",
          targetUid: targetUid ?? "",
          type: type ?? "",
          message: message ?? "",
          status: "failed",
          error: errMsg,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  }
);

// ============================================================================
// 이상 근태 알림 — 퇴근 시점 (attendance 문서 업데이트 트리거)
//
// 중복 방지: before.clockOut == null && after.clockOut != null 정밀 조건
// 비용 절약: Cloud Function 트리거만 (Firestore stream 아님)
// 정상 출퇴근은 발송하지 않음 (이상 근태만)
// ============================================================================

export const sendAttendancePush = onDocumentUpdated(
  {
    document: "attendance/{attendanceId}",
    region: "asia-northeast3",       // #5 서울 리전
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const storeId = after.storeId as string | undefined;
    if (!storeId) return;

    // ── 퇴근 감지: before.clockOut == null && after.clockOut != null ──
    const wasClockOut = before.clockOut != null && before.clockOut !== "";
    const isClockOut = after.clockOut != null && after.clockOut !== "";

    if (!wasClockOut && isClockOut) {
      const status = after.attendanceStatus as string | undefined;
      const abnormalStatuses = ["early_leave_pending", "pending_overtime", "pending_approval", "Unplanned"];
      if (status && abnormalStatuses.includes(status)) {
        const staffId = after.staffId as string | undefined;
        let workerName = after.workerName as string | undefined;

        if (!workerName && staffId) {
          try {
            const workerDoc = await admin.firestore().collection(`stores/${storeId}/workers`).doc(staffId).get();
            if (workerDoc.exists) {
              workerName = workerDoc.data()?.name as string | undefined;
            }
          } catch (err) {
            logger.error("Failed to fetch worker name for clockOut push", err);
          }
        }

        const name = workerName ?? staffId ?? "직원";
        const topic = `store_${storeId}_boss`;

        let pushTitle = "🔔 근태 알림";
        let pushBody = `${name}님의 근태를 확인해 주세요.`;

        if (status === "early_leave_pending") {
          pushTitle = "⚠️ 조기 퇴근 요청";
          pushBody = `${name}님이 조기 퇴근을 요청했습니다. 확인해 주세요.`;
        } else if (status === "pending_overtime") {
          pushTitle = "⏰ 연장 근무 신청";
          pushBody = `${name}님이 연장 근무를 신청했습니다.`;
        }

        try {
          await admin.messaging().send({
            topic,
            notification: {title: pushTitle, body: pushBody},
            data: {
              type: "attendance_abnormal",
              storeId,
              attendanceId: event.params.attendanceId,
              route: "/attendance",
            },
            android: {collapseKey: `${storeId}_attendance`},   // #2
            apns: {headers: {"apns-collapse-id": `${storeId}_attendance`}},
          });
          logger.info("Attendance push sent (clockOut)", {storeId, status});
        } catch (error) {
          logger.error("Attendance push failed", error);
        }
      }
    }
  }
);

// ============================================================================
// 이상 근태 알림 — 출근 시점 (attendance 문서 신규 생성 트리거)
// ============================================================================

export const sendAttendanceCreatedPush = onDocumentCreated(
  {
    document: "attendance/{attendanceId}",
    region: "asia-northeast3",       // #5 서울 리전
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const storeId = data.storeId as string | undefined;
    if (!storeId) return;

    const status = data.attendanceStatus as string | undefined;
    const abnormalStatuses = ["pending_approval", "Unplanned"];
    if (!status || !abnormalStatuses.includes(status)) return;

    const staffId = data.staffId as string | undefined;
    let workerName = data.workerName as string | undefined;

    if (!workerName && staffId) {
      try {
        const workerDoc = await admin.firestore().collection(`stores/${storeId}/workers`).doc(staffId).get();
        if (workerDoc.exists) {
          workerName = workerDoc.data()?.name as string | undefined;
        }
      } catch (err) {
        logger.error("Failed to fetch worker name for attendance push", err);
      }
    }

    const name = workerName ?? staffId ?? "직원";

    const topic = `store_${storeId}_boss`;
    const pushTitle = status === "Unplanned"
      ? "📋 휴무일 출근"
      : "⚠️ 이상 출근 감지";
    const pushBody = status === "Unplanned"
      ? `${name}님이 근무표에 없는 날 출근했습니다. 승인이 필요합니다.`
      : `${name}님의 출근 시간이 근무표와 다릅니다. 확인해 주세요.`;

    try {
      await admin.messaging().send({
        topic,
        notification: {title: pushTitle, body: pushBody},
        data: {
          type: "attendance_abnormal",
          storeId,
          attendanceId: event.params.attendanceId,
          route: "/attendance",
        },
        android: {collapseKey: `${storeId}_attendance`},   // #2
        apns: {headers: {"apns-collapse-id": `${storeId}_attendance`}},
      });
      logger.info("Attendance created push sent", {storeId, status});
    } catch (error) {
      logger.error("Attendance created push failed", error);
    }
  }
);

// ============================================================================
// 공지사항 알림 (사장님이 공지 작성 → 모든 알바생에게 푸시)
// Topic: store_{storeId}_workers (전체 알바생 구독)
// ============================================================================

export const sendNoticePush = onDocumentCreated(
  {
    document: "stores/{storeId}/notices/{noticeId}",
    region: "asia-northeast3",       // #5 서울 리전
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const storeId = event.params.storeId;
    const noticeTitle = data.title as string | undefined;

    const topic = `store_${storeId}_workers`;
    const payload: admin.messaging.Message = {
      topic,
      notification: {
        title: "📢 새 공지사항",
        body: noticeTitle ? `새 공지: ${noticeTitle}` : "새 공지사항이 등록되었습니다.",
      },
      data: {
        type: "notice",
        storeId,
        noticeId: event.params.noticeId,
        route: "/notices",
      },
      android: {collapseKey: `${storeId}_notice`},   // #2
      apns: {headers: {"apns-collapse-id": `${storeId}_notice`}},
    };

    try {
      await admin.messaging().send(payload);
      logger.info("Notice push sent", {topic, storeId, noticeId: event.params.noticeId});
    } catch (error) {
      logger.error("Failed to send notice push", error);
    }
  }
);

// ============================================================================
// notificationLogs / notificationQueue 자동 정리 (#4 Lifecycle 관리)
//
// 매일 새벽 4시 실행:
// - notificationLogs: 90일 초과 문서 삭제
// - notificationQueue: sent/failed 상태이고 30일 초과 문서 삭제
// ============================================================================

export const cleanupNotificationLogs = onSchedule(
  {
    schedule: "every day 04:00",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",        // #5
  },
  async () => {
    const db = admin.firestore();
    const now = new Date();

    // ── notificationLogs: 90일 초과 삭제 ──
    const logCutoff = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    const oldLogs = await db
      .collection("notificationLogs")
      .where("sentAt", "<", logCutoff)
      .limit(500)
      .get();

    let logDeleted = 0;
    const logBatch = db.batch();
    for (const doc of oldLogs.docs) {
      logBatch.delete(doc.ref);
      logDeleted++;
    }
    if (logDeleted > 0) {
      await logBatch.commit();
      logger.info(`Cleaned up ${logDeleted} old notification logs`);
    }

    // ── notificationQueue: sent/failed이고 30일 초과 삭제 ──
    const queueCutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    for (const status of ["sent", "failed", "rate_limited"]) {
      const oldQueue = await db
        .collection("notificationQueue")
        .where("status", "==", status)
        .limit(500)
        .get();

      const qBatch = db.batch();
      let qDeleted = 0;
      for (const doc of oldQueue.docs) {
        const createdAt = doc.data().createdAt;
        if (createdAt && createdAt.toDate() < queueCutoff) {
          qBatch.delete(doc.ref);
          qDeleted++;
        }
      }
      if (qDeleted > 0) {
        await qBatch.commit();
        logger.info(`Cleaned up ${qDeleted} old queue docs (status=${status})`);
      }
    }
  }
);

// R2 Storage Controller (generateUploadUrl, finalizeUpload, generateDownloadUrl)
export * from "./storage/r2_controller";
