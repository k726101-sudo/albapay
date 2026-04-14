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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendSpecialClausePush = exports.cleanupDemoSandbox = exports.sendSubstitutionPush = exports.appleSignInAndroidBridge = void 0;
const admin = __importStar(require("firebase-admin"));
const express_1 = __importDefault(require("express"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firebase_functions_1 = require("firebase-functions");
admin.initializeApp();
/** Android `sign_in_with_apple`: Apple `form_post` → intent:// 로 앱에 code / id_token 전달 */
const ANDROID_PACKAGE_ID = "com.standard.albapay";
const appleBridgeApp = (0, express_1.default)();
appleBridgeApp.use(express_1.default.urlencoded({ extended: true }));
appleBridgeApp.get("/", (_req, res) => {
    res
        .status(200)
        .type("text/plain")
        .send("Apple Sign-In Android bridge. POST only. Deploy 후 이 HTTPS URL을 Apple Services ID Return URLs에 넣으세요.");
});
appleBridgeApp.post("/", (req, res) => {
    const raw = req.body;
    const code = raw?.code ?? "";
    const id_token = raw?.id_token ?? "";
    const state = raw?.state ?? "";
    const user = raw?.user;
    if (!code) {
        firebase_functions_1.logger.error("appleSignInAndroidBridge: missing code", {
            rawKeys: raw ? Object.keys(raw) : [],
        });
        res.status(400).send("missing code");
        return;
    }
    const params = new URLSearchParams();
    params.set("code", String(code));
    if (id_token)
        params.set("id_token", String(id_token));
    if (state)
        params.set("state", String(state));
    if (user)
        params.set("user", String(user));
    const qs = params.toString();
    const intent = `intent://callback?${qs}#Intent;package=${ANDROID_PACKAGE_ID};scheme=signinwithapple;end`;
    res.redirect(302, intent);
});
exports.appleSignInAndroidBridge = (0, https_1.onRequest)({
    region: "asia-northeast3",
    cors: false,
    invoker: "public",
}, appleBridgeApp);
exports.sendSubstitutionPush = (0, firestore_1.onDocumentCreated)("stores/{storeId}/notifications/{notificationId}", async (event) => {
    const data = event.data?.data();
    if (!data || data.type != "substitution_request")
        return;
    const storeId = data.storeId ?? event.params.storeId;
    if (!storeId)
        return;
    const title = data.title ?? "대근 신청 도착";
    const body = data.message ??
        `${data.proposerName ?? "대근자"} 신청 · 주간 ${(data.proposerWeeklyPlannedHours ?? 0).toFixed(1)}h · 15시간 초과: ${data.over15Hours ? "예" : "아니오"}`;
    const topic = `store_${storeId}_boss`;
    const payload = {
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
        firebase_functions_1.logger.info("Substitution push sent", { topic, storeId });
    }
    catch (error) {
        firebase_functions_1.logger.error("Failed to send substitution push", error);
    }
});
/**
 * 데모 모드(체험하기)로 생성된 가짜 데이터 및 매장을 매일 새벽 3시에 일괄 정리하는 크론잡
 */
exports.cleanupDemoSandbox = (0, scheduler_1.onSchedule)({
    schedule: "every day 03:00",
    timeZone: "Asia/Seoul",
}, async () => {
    const db = admin.firestore();
    const batchSize = 500;
    try {
        // 1. isDemo: true 태그가 달린 가상 매장들을 가져옵니다.
        const demoStoresSnap = await db.collection("stores").where("isDemo", "==", true).get();
        if (demoStoresSnap.empty) {
            firebase_functions_1.logger.info("No demo stores to clean up.");
            return;
        }
        firebase_functions_1.logger.info(`Found ${demoStoresSnap.size} demo stores to delete.`);
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
                firebase_functions_1.logger.info(`Deleted ${attendanceSnap.size} attendance records for demo store ${storeId}`);
            }
            // 3. 매장에 소속된 가상 사장님(users) 계정 데이터 삭제
            if (ownerId) {
                try {
                    await db.collection("users").doc(ownerId).delete();
                    // Firebase Auth 익명 유저 삭제 (선택적)
                    await admin.auth().deleteUser(ownerId).catch(() => {
                        // 이미 토큰 만료로 삭제되었거나 에러 난 경우 무시
                    });
                }
                catch (e) {
                    firebase_functions_1.logger.warn(`Failed to delete demo user ${ownerId}`, e);
                }
            }
            // 4. 매장 문서 및 그 하위의 모든 컬렉션(workers, rosterDays 등) 재귀적 영구 삭제
            await db.recursiveDelete(storeDoc.ref);
            firebase_functions_1.logger.info(`Successfully wiped out demo store data: ${storeId}`);
        }
        firebase_functions_1.logger.info("Demo sandbox cleanup completed successfully.");
    }
    catch (error) {
        firebase_functions_1.logger.error("Error cleaning up demo sandboxes", error);
    }
});
/**
 * 특별 조항으로 인해 5인 미만 -> 5인 이상 사업장으로 변경될 경우 푸시 발송
 */
exports.sendSpecialClausePush = (0, firestore_1.onDocumentUpdated)("stores/{storeId}", async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after)
        return;
    const wasFiveOrMore = before.isFiveOrMore === true;
    const isFiveOrMore = after.isFiveOrMore === true;
    const reason = after.fiveOrMoreDecisionReason || "";
    // 5인 미만에서 5인 이상으로 넘어갔으며, 특별 조항 때문인지 확인
    if (!wasFiveOrMore && isFiveOrMore && reason.includes("특별 조항")) {
        const storeId = event.params.storeId;
        const topic = `store_${storeId}_boss`;
        const payload = {
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
            firebase_functions_1.logger.info("Special clause push sent", { topic, storeId });
        }
        catch (error) {
            firebase_functions_1.logger.error("Failed to send special clause push", error);
        }
    }
});
