"use strict";
/**
 * Firebase Cloud Functions for LITE Retail App
 *
 * Includes:
 * - createPaymentLink: Creates Razorpay payment links for sharing
 * - razorpayWebhook: Handles Razorpay payment status updates (signature-verified)
 * - sendRegistrationOTP: Sends email OTP for registration verification
 * - verifyRegistrationOTP: Verifies email OTP during registration
 * - onUserDeleted: Cleans up Firestore user document when Auth user is deleted
 * - generateDesktopToken: Custom auth token for Windows desktop sign-in
 * - onNewUserSignup: Welcome notification + admin alert on shop setup
 * - sendPushNotification: FCM push when notification doc is created
 * - cleanupOldNotifications: Scheduled daily cleanup of old read notifications
 * - scheduledFirestoreBackup: Daily automated Firestore export to Cloud Storage
 */
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
exports.seedUserUsage = exports.scheduledFirestoreBackup = exports.sendNotificationToPlan = exports.sendNotificationToAll = exports.getSubscriptionLimits = exports.seedAdmins = exports.onCustomerDeleted = exports.onCustomerCreated = exports.onProductDeleted = exports.onProductCreated = exports.onBillCreated = exports.processReferralReward = exports.redeemReferralCode = exports.onSubscriptionWrite = exports.generateMonthlyReport = exports.exchangeIdToken = exports.sendDailySalesSummary = exports.checkChurnedUsers = exports.checkSubscriptionExpiry = exports.activateSubscription = exports.createSubscription = exports.checkLowStock = exports.cleanupOldNotifications = exports.sendPushNotification = exports.onNewUserSignup = exports.generateDesktopToken = exports.deleteUserAccount = exports.onUserDeleted = exports.verifyRegistrationOTP = exports.sendRegistrationOTP = exports.razorpayWebhook = exports.createPaymentLink = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
const nodemailer = __importStar(require("nodemailer"));
admin.initializeApp();
// ─── Email Config (Brevo) ───
const getEmailTransporter = () => {
    return nodemailer.createTransport({
        host: "smtp-relay.brevo.com",
        port: 587,
        secure: false,
        auth: {
            user: process.env.BREVO_SMTP_USER || process.env.BREVO_EMAIL || "",
            pass: process.env.BREVO_API_KEY || "",
        },
    });
};
// ─── Razorpay Config ───
// Set in functions/.env file (auto-loaded by Firebase)
const getRazorpayConfig = () => {
    return {
        keyId: process.env.RAZORPAY_KEY_ID || "",
        keySecret: process.env.RAZORPAY_KEY_SECRET || "",
        webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || "",
    };
};
/**
 * Create a Razorpay Payment Link
 *
 * This function creates a shareable payment link that customers can use
 * to pay via UPI, cards, or netbanking.
 */
exports.createPaymentLink = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data, context) => {
    var _a;
    // Verify authentication (optional but recommended)
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to create payment links");
    }
    // Validate input
    if (!data.amount || data.amount <= 0) {
        throw new functions.https.HttpsError("invalid-argument", "Amount must be greater than 0");
    }
    if (!data.customerName || !data.customerPhone) {
        throw new functions.https.HttpsError("invalid-argument", "Customer name and phone are required");
    }
    const razorpayConfig = getRazorpayConfig();
    // Check if Razorpay is configured
    if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
        console.error("Razorpay not configured:", {
            hasKeyId: !!razorpayConfig.keyId,
            hasKeySecret: !!razorpayConfig.keySecret
        });
        throw new functions.https.HttpsError("failed-precondition", "Razorpay is not configured. Set razorpay.key_id and razorpay.key_secret");
    }
    try {
        // Convert amount to paise
        const amountInPaise = Math.round(data.amount * 100);
        // Create payment link via Razorpay API
        const auth = Buffer.from(`${razorpayConfig.keyId}:${razorpayConfig.keySecret}`).toString("base64");
        console.log("Creating Razorpay payment link for amount:", data.amount);
        const response = await fetch("https://api.razorpay.com/v1/payment_links", {
            method: "POST",
            headers: {
                "Authorization": `Basic ${auth}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                amount: amountInPaise,
                currency: "INR",
                description: data.description || `Payment to ${data.shopName || "Store"}`,
                customer: {
                    name: data.customerName,
                    contact: data.customerPhone.startsWith("+91")
                        ? data.customerPhone
                        : `+91${data.customerPhone.replace(/\D/g, "").slice(-10)}`,
                },
                notify: {
                    sms: true,
                    email: false,
                },
                reminder_enable: true,
                notes: {
                    bill_id: data.billId || "",
                    shop_name: data.shopName || "",
                },
            }),
        });
        const result = await response.json();
        if (!response.ok) {
            console.error("Razorpay API error:", result);
            const errorDesc = ((_a = result.error) === null || _a === void 0 ? void 0 : _a.description) || "Failed to create payment link";
            return {
                success: false,
                error: errorDesc,
            };
        }
        console.log("Razorpay payment link created:", result.short_url);
        // Log the transaction (optional)
        try {
            await admin.firestore().collection("payment_links").add({
                paymentLinkId: result.id,
                amount: data.amount,
                customerName: data.customerName,
                customerPhone: data.customerPhone,
                billId: data.billId || null,
                createdBy: context.auth.uid,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "created",
                shortUrl: result.short_url,
            });
        }
        catch (dbError) {
            console.warn("Failed to log payment link:", dbError);
        }
        return {
            success: true,
            paymentLink: result.short_url,
            paymentLinkId: result.id,
            shortUrl: result.short_url,
        };
    }
    catch (error) {
        console.error("Error creating payment link:", error);
        return {
            success: false,
            error: error instanceof Error ? error.message : "Unknown error",
        };
    }
});
/**
 * Webhook handler for Razorpay payment status updates
 *
 * Configure this URL in Razorpay Dashboard -> Settings -> Webhooks
 * IMPORTANT: Set the webhook secret via:
 *   firebase functions:config:set razorpay.webhook_secret="your_webhook_secret"
 */
exports.razorpayWebhook = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onRequest(async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o;
    if (req.method !== "POST") {
        res.status(405).send("Method not allowed");
        return;
    }
    try {
        // ─── Verify Razorpay webhook signature ───
        const razorpayConfig = getRazorpayConfig();
        const webhookSecret = razorpayConfig.webhookSecret;
        if (!webhookSecret) {
            console.error("Razorpay webhook secret not configured");
            res.status(500).send("Webhook secret not configured");
            return;
        }
        const signature = req.headers["x-razorpay-signature"];
        if (!signature) {
            console.warn("Missing x-razorpay-signature header — rejecting request");
            res.status(401).send("Unauthorized: missing signature");
            return;
        }
        // Compute expected signature: HMAC-SHA256 of raw body with webhook secret
        const rawBody = req.rawBody || (typeof req.body === "string" ? req.body : JSON.stringify(req.body));
        const expectedSignature = crypto
            .createHmac("sha256", webhookSecret)
            .update(rawBody)
            .digest("hex");
        if (signature !== expectedSignature) {
            console.warn("Invalid webhook signature — possible spoofing attempt");
            res.status(401).send("Unauthorized: invalid signature");
            return;
        }
        // ─── Signature verified ───
        const event = req.body;
        console.log("Received webhook event:", event.event);
        // Handle payment events
        switch (event.event) {
            case "payment_link.paid":
                const paymentLinkId = (_b = (_a = event.payload.payment_link) === null || _a === void 0 ? void 0 : _a.entity) === null || _b === void 0 ? void 0 : _b.id;
                if (paymentLinkId) {
                    // Update payment link status in Firestore
                    const snapshot = await admin.firestore()
                        .collection("payment_links")
                        .where("paymentLinkId", "==", paymentLinkId)
                        .get();
                    if (!snapshot.empty) {
                        const doc = snapshot.docs[0];
                        await doc.ref.update({
                            status: "paid",
                            paidAt: admin.firestore.FieldValue.serverTimestamp(),
                            paymentId: (_d = (_c = event.payload.payment) === null || _c === void 0 ? void 0 : _c.entity) === null || _d === void 0 ? void 0 : _d.id,
                        });
                        console.log("Payment link marked as paid:", paymentLinkId);
                    }
                }
                break;
            case "payment_link.expired":
                console.log("Payment link expired");
                break;
            // ─── Subscription lifecycle events ───
            case "subscription.activated": {
                // First payment succeeded — activate plan in user doc
                // This is the FALLBACK for mobile payments where the JS callback was lost
                const subId = (_f = (_e = event.payload.subscription) === null || _e === void 0 ? void 0 : _e.entity) === null || _f === void 0 ? void 0 : _f.id;
                if (subId) {
                    const subSnap = await admin.firestore()
                        .collection("razorpay_subscriptions")
                        .doc(subId)
                        .get();
                    if (subSnap.exists) {
                        const subData = subSnap.data();
                        const activatedUserId = subData.userId;
                        const activatedPlan = subData.plan;
                        const activatedCycle = subData.cycle;
                        if (activatedUserId && activatedPlan) {
                            // Check if plan is already activated (activateSubscription may have run first)
                            const userDoc = await admin.firestore().collection("users").doc(activatedUserId).get();
                            const currentSub = (_g = userDoc.data()) === null || _g === void 0 ? void 0 : _g.subscription;
                            const alreadyActive = (currentSub === null || currentSub === void 0 ? void 0 : currentSub.plan) === activatedPlan && (currentSub === null || currentSub === void 0 ? void 0 : currentSub.status) === "active";
                            if (!alreadyActive) {
                                const daysToAdd = activatedCycle === "annual" ? 365 : 30;
                                const expiresAt = new Date();
                                expiresAt.setDate(expiresAt.getDate() + daysToAdd);
                                const billsLimit = activatedPlan === "pro" ? 500 : 999999;
                                await admin.firestore().collection("users").doc(activatedUserId).update({
                                    "subscription.plan": activatedPlan,
                                    "subscription.status": "active",
                                    "subscription.startedAt": admin.firestore.FieldValue.serverTimestamp(),
                                    "subscription.expiresAt": admin.firestore.Timestamp.fromDate(expiresAt),
                                    "subscription.razorpaySubscriptionId": subId,
                                    "limits.billsLimit": billsLimit,
                                    "limits.productsLimit": 999999,
                                    "limits.customersLimit": 999999,
                                });
                                // Welcome notification
                                await admin.firestore().collection("users").doc(activatedUserId)
                                    .collection("notifications").add({
                                    title: `Welcome to ${activatedPlan === "pro" ? "Pro" : "Business"} Plan! 🎉`,
                                    body: `Your ${activatedPlan === "pro" ? "Pro" : "Business"} plan is now active. Enjoy ${activatedPlan === "pro" ? "500 bills/month" : "unlimited billing"}!`,
                                    type: "subscription",
                                    read: false,
                                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                                });
                                console.log(`subscription.activated (webhook fallback): activated ${activatedPlan} for user ${activatedUserId}`);
                            }
                            else {
                                console.log(`subscription.activated: user ${activatedUserId} already on ${activatedPlan}, skipping`);
                            }
                        }
                        await subSnap.ref.update({ status: "active" });
                        console.log("Subscription activated:", subId);
                    }
                }
                break;
            }
            case "subscription.charged": {
                // Auto-renewal payment succeeded — extend expiry and reset monthly counter
                const chargedSubId = (_j = (_h = event.payload.subscription) === null || _h === void 0 ? void 0 : _h.entity) === null || _j === void 0 ? void 0 : _j.id;
                if (!chargedSubId)
                    break;
                const chargedSnap = await admin.firestore()
                    .collection("razorpay_subscriptions")
                    .doc(chargedSubId)
                    .get();
                if (!chargedSnap.exists) {
                    console.warn("subscription.charged: unknown subscription", chargedSubId);
                    break;
                }
                const { userId: chargedUserId, cycle } = chargedSnap.data();
                const daysToAdd = cycle === "annual" ? 365 : 30;
                const newExpiry = new Date();
                newExpiry.setDate(newExpiry.getDate() + daysToAdd);
                await admin.firestore().collection("users").doc(chargedUserId).update({
                    "subscription.status": "active",
                    "subscription.expiresAt": admin.firestore.Timestamp.fromDate(newExpiry),
                    "limits.billsThisMonth": 0,
                    "limits.lastResetMonth": `${newExpiry.getFullYear()}-${String(newExpiry.getMonth() + 1).padStart(2, "0")}`,
                });
                console.log(`subscription.charged: extended expiry for user ${chargedUserId} to ${newExpiry.toISOString()}`);
                // Send renewal success notification
                await admin.firestore().collection("users").doc(chargedUserId)
                    .collection("notifications").add({
                    title: "Subscription Renewed! 🎉",
                    body: `Your plan has been renewed. Next billing: ${newExpiry.toLocaleDateString("en-IN")}`,
                    type: "subscription",
                    read: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                break;
            }
            case "subscription.halted": {
                // Payment failed 3 times — downgrade user to free
                const haltedSubId = (_l = (_k = event.payload.subscription) === null || _k === void 0 ? void 0 : _k.entity) === null || _l === void 0 ? void 0 : _l.id;
                if (!haltedSubId)
                    break;
                const haltedSnap = await admin.firestore()
                    .collection("razorpay_subscriptions")
                    .doc(haltedSubId)
                    .get();
                if (!haltedSnap.exists)
                    break;
                const { userId: haltedUserId } = haltedSnap.data();
                await admin.firestore().collection("users").doc(haltedUserId).update({
                    "subscription.status": "expired",
                    "subscription.plan": "free",
                    "limits.billsLimit": 50,
                    "limits.productsLimit": 100,
                    "limits.customersLimit": 10,
                });
                await haltedSnap.ref.update({ status: "halted" });
                console.log(`subscription.halted: downgraded user ${haltedUserId} to free`);
                // Notify user
                await admin.firestore().collection("users").doc(haltedUserId)
                    .collection("notifications").add({
                    title: "Payment Failed — Plan Downgraded",
                    body: "We couldn't process your renewal payment. You've been moved to the Free plan. Please update your payment method to resubscribe.",
                    type: "subscription",
                    read: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                break;
            }
            case "subscription.cancelled": {
                // User cancelled — keep access till expiresAt, then it expires naturally
                const cancelledSubId = (_o = (_m = event.payload.subscription) === null || _m === void 0 ? void 0 : _m.entity) === null || _o === void 0 ? void 0 : _o.id;
                if (!cancelledSubId)
                    break;
                const cancelledSnap = await admin.firestore()
                    .collection("razorpay_subscriptions")
                    .doc(cancelledSubId)
                    .get();
                if (!cancelledSnap.exists)
                    break;
                const { userId: cancelledUserId } = cancelledSnap.data();
                await admin.firestore().collection("users").doc(cancelledUserId).update({
                    "subscription.status": "cancelled",
                });
                await cancelledSnap.ref.update({ status: "cancelled" });
                console.log(`subscription.cancelled: marked user ${cancelledUserId}`);
                break;
            }
            default:
                console.log("Unhandled webhook event:", event.event);
        }
        res.status(200).send("OK");
    }
    catch (error) {
        console.error("Webhook error:", error);
        res.status(500).send("Internal error");
    }
});
// ─── Pre-Registration Email OTP ───
/**
 * Send a 6-digit OTP to an email BEFORE account creation
 * No authentication required — used during registration
 */
exports.sendRegistrationOTP = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data) => {
    var _a, _b, _c, _d;
    const email = (_b = (_a = data.email) === null || _a === void 0 ? void 0 : _a.trim()) === null || _b === void 0 ? void 0 : _b.toLowerCase();
    if (!email || !/^[^@]+@[^@]+\.[^@]+$/.test(email)) {
        return { success: false, error: "Please enter a valid email address" };
    }
    const db = admin.firestore();
    // Use email hash as document ID (safe for Firestore)
    const emailKey = crypto.createHash("sha256").update(email).digest("hex").substring(0, 20);
    const otpRef = db.collection("registration_otps").doc(emailKey);
    // Rate limit: 1 OTP per minute
    const existing = await otpRef.get();
    if (existing.exists) {
        const lastSent = (_d = (_c = existing.data()) === null || _c === void 0 ? void 0 : _c.sentAt) === null || _d === void 0 ? void 0 : _d.toDate();
        if (lastSent && Date.now() - lastSent.getTime() < 60000) {
            const waitSecs = Math.ceil((60000 - (Date.now() - lastSent.getTime())) / 1000);
            return {
                success: false,
                error: `Please wait ${waitSecs} seconds before requesting a new code`,
            };
        }
    }
    // Generate 6-digit OTP (cryptographically secure)
    const otp = crypto.randomInt(100000, 999999).toString();
    // Store OTP with 10-minute expiry
    await otpRef.set({
        code: otp,
        email: email,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
        attempts: 0,
    });
    // Send email via Brevo
    try {
        const transporter = getEmailTransporter();
        await transporter.sendMail({
            from: `"Tulasi Stores" <${process.env.BREVO_EMAIL}>`,
            to: email,
            subject: "Your Verification Code - Tulasi Stores",
            html: `
                    <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px; background: #f8faf8; border-radius: 12px;">
                        <div style="text-align: center; margin-bottom: 24px;">
                            <h2 style="color: #059669; margin: 0;">Tulasi Stores</h2>
                            <p style="color: #6b7280; font-size: 14px; margin-top: 4px;">Email Verification</p>
                        </div>
                        <div style="background: white; border-radius: 8px; padding: 24px; text-align: center; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                            <p style="color: #374151; font-size: 15px; margin-bottom: 16px;">Your verification code is:</p>
                            <div style="font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #059669; background: #ecfdf5; padding: 16px; border-radius: 8px; margin: 16px 0;">
                                ${otp}
                            </div>
                            <p style="color: #9ca3af; font-size: 13px; margin-top: 16px;">This code expires in <strong>10 minutes</strong></p>
                        </div>
                        <p style="color: #9ca3af; font-size: 12px; text-align: center; margin-top: 16px;">If you didn't request this, please ignore this email.</p>
                    </div>
                `,
        });
        console.log(`📧 Registration OTP sent to ${email}`);
        return { success: true };
    }
    catch (emailError) {
        console.error("Failed to send OTP email:", emailError);
        await otpRef.delete();
        const detail = (emailError === null || emailError === void 0 ? void 0 : emailError.response) || (emailError === null || emailError === void 0 ? void 0 : emailError.message) || "Unknown error";
        return {
            success: false,
            error: `Email sending failed: ${detail}`,
        };
    }
});
/**
 * Verify pre-registration OTP
 * No authentication required — used during registration
 */
exports.verifyRegistrationOTP = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data) => {
    var _a, _b, _c, _d;
    const email = (_b = (_a = data.email) === null || _a === void 0 ? void 0 : _a.trim()) === null || _b === void 0 ? void 0 : _b.toLowerCase();
    const { otp } = data;
    if (!email || !otp || otp.length !== 6) {
        return { success: false, error: "Please enter a valid 6-digit code" };
    }
    const db = admin.firestore();
    const emailKey = crypto.createHash("sha256").update(email).digest("hex").substring(0, 20);
    const otpRef = db.collection("registration_otps").doc(emailKey);
    const otpDoc = await otpRef.get();
    if (!otpDoc.exists) {
        return { success: false, error: "No code found. Please request a new one." };
    }
    const otpData = otpDoc.data();
    // Check max attempts (5 tries)
    if (otpData.attempts >= 5) {
        await otpRef.delete();
        return { success: false, error: "Too many attempts. Please request a new code." };
    }
    // Check expiry
    const expiresAt = ((_d = (_c = otpData.expiresAt) === null || _c === void 0 ? void 0 : _c.toDate) === null || _d === void 0 ? void 0 : _d.call(_c)) || new Date(0);
    if (Date.now() > expiresAt.getTime()) {
        await otpRef.delete();
        return { success: false, error: "Code has expired. Please request a new one." };
    }
    // Increment attempts
    await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    // Verify code
    if (otpData.code !== otp) {
        const remaining = 5 - (otpData.attempts + 1);
        return {
            success: false,
            error: `Incorrect code. ${remaining} attempt${remaining !== 1 ? "s" : ""} remaining.`,
        };
    }
    // OTP verified! Clean up
    await otpRef.delete();
    console.log(`✅ Registration OTP verified for ${email}`);
    return { success: true };
});
// ─── Auth User Cleanup ───
/**
 * Delete all user-scoped subcollections (CF8 shared helper).
 * Used by both onUserDeleted and deleteUserAccount.
 */
async function deleteUserSubcollections(uid) {
    const db = admin.firestore();
    const userDocRef = db.collection("users").doc(uid);
    const subCollections = [
        "products", "bills", "customers", "transactions",
        "expenses", "notifications", "counters", "settings",
        "attendance", "subscription_audit",
    ];
    let totalDeleted = 0;
    for (const collName of subCollections) {
        let hasMore = true;
        while (hasMore) {
            const snapshot = await userDocRef.collection(collName).limit(400).get();
            if (snapshot.empty) {
                hasMore = false;
                continue;
            }
            if (collName === "customers") {
                for (const customerDoc of snapshot.docs) {
                    let innerHasMore = true;
                    while (innerHasMore) {
                        const txnSnap = await customerDoc.ref.collection("transactions").limit(400).get();
                        if (txnSnap.empty) {
                            innerHasMore = false;
                            continue;
                        }
                        const innerBatch = db.batch();
                        txnSnap.docs.forEach((doc) => innerBatch.delete(doc.ref));
                        await innerBatch.commit();
                        totalDeleted += txnSnap.size;
                    }
                }
            }
            const batch = db.batch();
            snapshot.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            totalDeleted += snapshot.size;
        }
    }
    return totalDeleted;
}
/**
 * Automatically clean up Firestore user document when a user is deleted from Firebase Auth.
 * Now also deletes all subcollections (CF8).
 */
exports.onUserDeleted = functions
    .region("asia-south1")
    .auth.user().onDelete(async (user) => {
    const uid = user.uid;
    const email = user.email || "unknown";
    console.log(`🗑️ Auth user deleted: ${email} (${uid}). Cleaning up Firestore...`);
    const db = admin.firestore();
    try {
        // Delete all subcollections first (CF8)
        const totalDeleted = await deleteUserSubcollections(uid);
        console.log(`🗑️ Deleted ${totalDeleted} subcollection docs for ${uid}`);
        // Delete the user document from Firestore
        const userDoc = db.collection("users").doc(uid);
        const doc = await userDoc.get();
        if (doc.exists) {
            const data = doc.data();
            console.log(`🗑️ Deleting Firestore user doc: phone=${data === null || data === void 0 ? void 0 : data.phone}, shop=${data === null || data === void 0 ? void 0 : data.shopName}`);
            await userDoc.delete();
            console.log(`✅ Firestore user doc deleted for ${email}`);
        }
        else {
            console.log(`ℹ️ No Firestore user doc found for ${uid}`);
        }
    }
    catch (error) {
        console.error(`❌ Error cleaning up Firestore for ${uid}:`, error);
    }
});
// ─── Account Deletion (DPDP Act + Google Play Policy) ───
/**
 * Callable function to delete a user's account and ALL associated data.
 * Required by Google Play policy (Dec 2023) and India's DPDP Act 2023.
 *
 * Deletes: user doc, all sub-collections (products, bills, customers,
 * transactions, expenses, notifications, counters, settings, attendance),
 * Storage files, and finally the Firebase Auth account.
 */
exports.deleteUserAccount = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 300, memory: "512MB", maxInstances: 20 })
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated to delete their account");
    }
    const uid = context.auth.uid;
    const email = context.auth.token.email || "unknown";
    console.log(`🗑️ Account deletion requested by: ${email} (${uid})`);
    const db = admin.firestore();
    const userDocRef = db.collection("users").doc(uid);
    // Sub-collections to delete (all user-scoped data)
    const subCollections = [
        "products",
        "bills",
        "customers",
        "transactions",
        "expenses",
        "notifications",
        "counters",
        "settings",
        "attendance",
    ];
    let totalDeleted = 0;
    try {
        // 1. Delete all sub-collections in batches of 400
        for (const collName of subCollections) {
            let hasMore = true;
            while (hasMore) {
                const snapshot = await userDocRef
                    .collection(collName)
                    .limit(400)
                    .get();
                if (snapshot.empty) {
                    hasMore = false;
                    continue;
                }
                // For customers, also delete nested transactions sub-collection
                if (collName === "customers") {
                    for (const customerDoc of snapshot.docs) {
                        let innerHasMore = true;
                        while (innerHasMore) {
                            const txnSnap = await customerDoc.ref
                                .collection("transactions")
                                .limit(400)
                                .get();
                            if (txnSnap.empty) {
                                innerHasMore = false;
                                continue;
                            }
                            const innerBatch = db.batch();
                            txnSnap.docs.forEach((doc) => innerBatch.delete(doc.ref));
                            await innerBatch.commit();
                            totalDeleted += txnSnap.size;
                        }
                    }
                }
                const batch = db.batch();
                snapshot.docs.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
                totalDeleted += snapshot.size;
            }
            console.log(`🗑️ Deleted sub-collection: ${collName}`);
        }
        // 2. Delete user_usage tracking doc
        try {
            await db.collection("user_usage").doc(uid).delete();
            totalDeleted++;
        }
        catch (_) {
            // May not exist
        }
        // 3. Delete user's Storage files (profile images, shop logos)
        try {
            const bucket = admin.storage().bucket();
            await bucket.deleteFiles({ prefix: `users/${uid}/` });
            console.log(`🗑️ Deleted Storage files for ${uid}`);
        }
        catch (e) {
            console.log(`ℹ️ Storage cleanup: ${e}`);
        }
        // 4. Delete the user document itself
        await userDocRef.delete();
        totalDeleted++;
        console.log(`🗑️ Deleted user document for ${uid}`);
        // 5. Delete Firebase Auth account (this is permanent)
        await admin.auth().deleteUser(uid);
        console.log(`✅ Account fully deleted: ${email} (${uid}). ${totalDeleted} documents removed.`);
        return {
            success: true,
            message: "Account and all data deleted successfully",
            documentsDeleted: totalDeleted,
        };
    }
    catch (error) {
        console.error(`❌ Account deletion failed for ${uid}:`, error);
        throw new functions.https.HttpsError("internal", "Failed to delete account. Please try again or contact support.");
    }
});
// ─── Desktop Auth Token ───
/**
 * Generate a custom auth token for desktop sign-in.
 *
 * Called by the web auth page after user completes login + shop setup.
 * The desktop app polls Firestore for the token, then uses
 * signInWithCustomToken() to authenticate.
 *
 * Flow:
 * 1. Desktop generates a linkCode, stores {status:"pending"} in Firestore
 * 2. Desktop opens web app /desktop-login?code=LINK_CODE
 * 3. User completes auth on web
 * 4. Web calls this function with the linkCode
 * 5. Function generates customToken and stores in Firestore
 * 6. Desktop polls Firestore, finds token, signs in
 */
exports.generateDesktopToken = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data, context) => {
    var _a;
    // Must be authenticated (web user just signed in)
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated");
    }
    const { linkCode } = data;
    if (!linkCode || linkCode.length < 6 || linkCode.length > 8) {
        throw new functions.https.HttpsError("invalid-argument", "Invalid link code");
    }
    const uid = context.auth.uid;
    const db = admin.firestore();
    try {
        // Verify the session exists and is pending
        const sessionRef = db.collection("desktop_auth_sessions").doc(linkCode);
        const session = await sessionRef.get();
        if (!session.exists) {
            throw new functions.https.HttpsError("not-found", "Session not found. Please try again from the desktop app.");
        }
        const sessionData = session.data();
        if (sessionData.status !== "pending") {
            throw new functions.https.HttpsError("already-exists", "This session has already been used.");
        }
        // Check session age (max 10 minutes)
        const createdAt = (_a = sessionData.createdAt) === null || _a === void 0 ? void 0 : _a.toDate();
        if (createdAt && Date.now() - createdAt.getTime() > 10 * 60 * 1000) {
            await sessionRef.delete();
            throw new functions.https.HttpsError("deadline-exceeded", "Session expired. Please try again from the desktop app.");
        }
        // Generate custom auth token
        const customToken = await admin.auth().createCustomToken(uid);
        // Store token in Firestore for desktop to pick up
        await sessionRef.update({
            status: "ready",
            customToken: customToken,
            uid: uid,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`🖥️ Desktop auth token generated for user ${uid}, code: ${linkCode}`);
        return { success: true };
    }
    catch (error) {
        if (error instanceof functions.https.HttpsError)
            throw error;
        console.error("Error generating desktop token:", error);
        throw new functions.https.HttpsError("internal", "Failed to generate auth token");
    }
});
// ─── Notification Cloud Functions ───
/**
 * Welcome notification when a new user completes shop setup.
 * Triggers on Firestore write when isShopSetupComplete changes to true.
 */
exports.onNewUserSignup = functions
    .region("asia-south1")
    .firestore.document("users/{userId}")
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const userId = context.params.userId;
    // Only trigger when shop setup transitions from false → true
    if (before.isShopSetupComplete || !after.isShopSetupComplete) {
        return;
    }
    const db = admin.firestore();
    const shopName = after.shopName || "your shop";
    const ownerName = after.ownerName || "there";
    console.log(`🎉 New user completed setup: ${ownerName} (${shopName})`);
    // 1. Send welcome notification to the new user
    await db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .add({
        title: "Welcome to RetailLite! 🎉",
        body: `Hi ${ownerName}, your shop "${shopName}" is all set up. Start adding products and making sales!`,
        type: "system",
        targetType: "user",
        targetUserId: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentBy: "system",
        read: false,
    });
    // 2. Notify all admins about the new signup
    const adminsSnapshot = await db
        .collection("admins")
        .get();
    const batch = db.batch();
    for (const adminDoc of adminsSnapshot.docs) {
        const adminNotifRef = db
            .collection("users")
            .doc(adminDoc.id)
            .collection("notifications")
            .doc();
        batch.set(adminNotifRef, {
            title: "New User Signup 🆕",
            body: `${ownerName} just created shop "${shopName}"`,
            type: "alert",
            targetType: "user",
            targetUserId: adminDoc.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            sentBy: "system",
            read: false,
        });
    }
    await batch.commit();
    // 3. Also log to global notifications collection
    await db.collection("notifications").add({
        title: "New User Signup",
        body: `${ownerName} created shop "${shopName}"`,
        type: "alert",
        targetType: "all",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentBy: "system",
    });
    console.log(`✅ Welcome + admin notifications sent for ${userId}`);
});
/**
 * Send FCM push notification when a notification document is created.
 * Listens on the user's notifications subcollection.
 */
exports.sendPushNotification = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/notifications/{notificationId}")
    .onCreate(async (snapshot, context) => {
    var _a;
    const userId = context.params.userId;
    const data = snapshot.data();
    if (!data)
        return;
    const title = data.title || "New Notification";
    const body = data.body || "";
    // Get user's FCM tokens
    const userDoc = await admin.firestore()
        .collection("users")
        .doc(userId)
        .get();
    const fcmTokens = (_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmTokens;
    if (!fcmTokens || fcmTokens.length === 0) {
        console.log(`📱 No FCM tokens for user ${userId}, skipping push`);
        return;
    }
    console.log(`📱 Sending push to ${fcmTokens.length} device(s) for user ${userId}`);
    // Send to all user's devices
    const message = {
        tokens: fcmTokens,
        notification: {
            title: title,
            body: body,
        },
        data: {
            type: data.type || "system",
            notificationId: context.params.notificationId,
        },
        webpush: {
            fcmOptions: {
                link: "/notifications",
            },
        },
    };
    try {
        const response = await admin.messaging().sendEachForMulticast(message);
        console.log(`📱 Push sent: ${response.successCount} success, ${response.failureCount} failures`);
        // Remove invalid tokens
        if (response.failureCount > 0) {
            const tokensToRemove = [];
            response.responses.forEach((resp, idx) => {
                var _a;
                if (!resp.success && ((_a = resp.error) === null || _a === void 0 ? void 0 : _a.code) === "messaging/registration-token-not-registered") {
                    tokensToRemove.push(fcmTokens[idx]);
                }
            });
            if (tokensToRemove.length > 0) {
                await admin.firestore().collection("users").doc(userId).update({
                    fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
                });
                console.log(`🗑️ Removed ${tokensToRemove.length} stale FCM token(s)`);
            }
        }
    }
    catch (error) {
        console.error("❌ FCM send error:", error);
    }
});
/**
 * Scheduled cleanup: delete read notifications older than 30 days.
 * Runs daily at midnight IST (18:30 UTC).
 * Uses cursor-paginated user iteration (200 users per page) to avoid full-collection scans.
 */
exports.cleanupOldNotifications = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 300, memory: "512MB", maxInstances: 3 })
    .pubsub.schedule("30 18 * * *") // 18:30 UTC = midnight IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    const db = admin.firestore();
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const PAGE_SIZE = 200;
    console.log("🧹 Cleaning up old notifications (paginated)...");
    let totalDeleted = 0;
    let lastDoc = null;
    do {
        let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const usersPage = await query.get();
        if (usersPage.empty)
            break;
        for (const userDoc of usersPage.docs) {
            const oldNotifs = await db
                .collection("users")
                .doc(userDoc.id)
                .collection("notifications")
                .where("read", "==", true)
                .where("createdAt", "<", thirtyDaysAgo)
                .limit(100)
                .get();
            if (!oldNotifs.empty) {
                const batch = db.batch();
                oldNotifs.docs.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
                totalDeleted += oldNotifs.size;
            }
        }
        lastDoc = usersPage.docs[usersPage.docs.length - 1];
    } while (true);
    console.log(`🧹 Cleaned up ${totalDeleted} old notifications`);
});
// ─── Automated Notification Triggers ───
/**
 * Low Stock Alert — triggers when a product's stock is updated.
 * Sends notification if stock falls at or below lowStockAlert threshold.
 * Respects user's settings.lowStockAlerts preference.
 */
exports.checkLowStock = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/products/{productId}")
    .onUpdate(async (change, context) => {
    var _a, _b;
    const before = change.before.data();
    const after = change.after.data();
    const userId = context.params.userId;
    const newStock = after.stock;
    const oldStock = before.stock;
    const threshold = (_a = after.lowStockAlert) !== null && _a !== void 0 ? _a : 5;
    const productName = after.name || "Product";
    // Only trigger if stock dropped and is now at/below threshold
    if (newStock >= oldStock || newStock > threshold) {
        return;
    }
    // Check user preference
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    const settings = ((_b = userDoc.data()) === null || _b === void 0 ? void 0 : _b.settings) || {};
    if (settings.lowStockAlerts === false) {
        console.log(`🔕 Low stock alerts disabled for user ${userId}`);
        return;
    }
    const isOutOfStock = newStock <= 0;
    const title = isOutOfStock
        ? `Out of Stock! ❌`
        : `Low Stock Alert ⚠️`;
    const body = isOutOfStock
        ? `${productName} is now out of stock. Reorder immediately!`
        : `${productName} has only ${newStock} left (threshold: ${threshold}). Consider reordering.`;
    console.log(`📦 ${title}: ${productName} (${newStock} remaining) for user ${userId}`);
    await admin.firestore()
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .add({
        title,
        body,
        type: "alert",
        targetType: "user",
        targetUserId: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentBy: "system",
        read: false,
        data: {
            trigger: "low_stock",
            productId: context.params.productId,
            productName,
            stock: newStock,
            threshold,
        },
    });
});
// ─── Razorpay Plan IDs (LIVE mode, ₹10/₹20/₹30 pricing) ───
// Created via API on 2026-04-03 with rzp_live_ key
// TEST plan IDs (for rzp_test_ key only):
//   pro:      { monthly: "plan_SY9W1ASLrxRreg", annual: "plan_SY9W1v4s3qPFcH" }
//   business: { monthly: "plan_SY9W2ApFAYQPYI", annual: "plan_SY9W2Q0ydG6k7G" }
// LIVE production pricing (swap when ready for real prices):
//   pro:      { monthly: "plan_SY9CBfmDTbSXHV", annual: "plan_SY9CPMsAtVz46Z" }
//   business: { monthly: "plan_SY9CYJ4KOmSdbr", annual: "plan_SY9ChNaBTBBnzj" }
const RAZORPAY_PLAN_IDS = {
    pro: {
        monthly: "plan_SYyyoXH8w6hPug",
        annual: "plan_SYyyp9wRAvfWr6",
    },
    business: {
        monthly: "plan_SYyypQRjwxYfDS",
        annual: "plan_SYyypdTKBAPxOh",
    },
};
/**
 * Create a Razorpay Subscription — called from Flutter before opening checkout.
 * Creates a subscription on Razorpay's side and returns the subscription ID
 * which the client uses to open the Razorpay checkout flow.
 *
 * Callable function: requires authenticated user.
 */
exports.createSubscription = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login required");
    }
    const { plan, cycle, customerEmail, customerPhone, customerName } = data;
    if (!plan || !cycle || !["pro", "business"].includes(plan) || !["monthly", "annual"].includes(cycle)) {
        throw new functions.https.HttpsError("invalid-argument", "Valid plan and cycle are required");
    }
    const razorpayConfig = getRazorpayConfig();
    if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
        throw new functions.https.HttpsError("failed-precondition", "Razorpay not configured");
    }
    const planId = (_a = RAZORPAY_PLAN_IDS[plan]) === null || _a === void 0 ? void 0 : _a[cycle];
    if (!planId) {
        throw new functions.https.HttpsError("not-found", `No Razorpay plan found for ${plan}/${cycle}`);
    }
    try {
        const auth = Buffer.from(`${razorpayConfig.keyId}:${razorpayConfig.keySecret}`).toString("base64");
        const totalCount = cycle === "annual" ? 1 : 12; // annual = 1 charge, monthly = 12 charges then renew
        const response = await fetch("https://api.razorpay.com/v1/subscriptions", {
            method: "POST",
            headers: {
                "Authorization": `Basic ${auth}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(Object.assign({ plan_id: planId, total_count: totalCount, quantity: 1, customer_notify: 1, notes: {
                    userId: context.auth.uid,
                    plan,
                    cycle,
                    customerName: customerName || "",
                    customerEmail: customerEmail || "",
                } }, (customerEmail || customerPhone ? {
                notify_info: Object.assign(Object.assign({}, (customerEmail ? { notify_email: customerEmail } : {})), (customerPhone ? { notify_phone: customerPhone } : {})),
            } : {}))),
        });
        const result = await response.json();
        if (!response.ok) {
            console.error("Razorpay create subscription error:", result);
            throw new functions.https.HttpsError("internal", ((_b = result === null || result === void 0 ? void 0 : result.error) === null || _b === void 0 ? void 0 : _b.description) || "Failed to create subscription");
        }
        console.log(`✅ createSubscription: ${result.id} for user ${context.auth.uid} (${plan}/${cycle})`);
        // Save subscription→user mapping so the webhook can activate the plan
        // even if the JS callback never fires (e.g. mobile UPI redirect)
        await admin.firestore().collection("razorpay_subscriptions").doc(result.id).set({
            userId: context.auth.uid,
            plan,
            cycle,
            planId,
            status: "created",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
            success: true,
            subscriptionId: result.id,
            planId,
            plan,
            cycle,
        };
    }
    catch (err) {
        if (err instanceof functions.https.HttpsError)
            throw err;
        console.error("createSubscription error:", err);
        throw new functions.https.HttpsError("internal", "Could not create subscription");
    }
});
/**
 * Activate Subscription — called from the Flutter app after a successful
 * Razorpay payment. Verifies the payment ID with Razorpay, then updates
 * the user's Firestore subscription and limits.
 *
 * Callable function: requires authenticated user.
 */
exports.activateSubscription = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 60, memory: "256MB", maxInstances: 50 })
    .https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login required");
    }
    let { plan, cycle } = data;
    const { razorpayPaymentId, razorpaySubscriptionId } = data;
    const userId = context.auth.uid;
    if (!razorpayPaymentId) {
        throw new functions.https.HttpsError("invalid-argument", "razorpayPaymentId is required");
    }
    const razorpayConfig = getRazorpayConfig();
    if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
        throw new functions.https.HttpsError("failed-precondition", "Razorpay not configured");
    }
    const auth = Buffer.from(`${razorpayConfig.keyId}:${razorpayConfig.keySecret}`).toString("base64");
    // Verify payment exists with Razorpay
    try {
        const verifyRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}`, { headers: { Authorization: `Basic ${auth}` } });
        if (!verifyRes.ok) {
            throw new functions.https.HttpsError("not-found", "Payment not found in Razorpay");
        }
        const payment = await verifyRes.json();
        if (payment.status !== "captured" && payment.status !== "authorized") {
            throw new functions.https.HttpsError("failed-precondition", `Payment status is ${payment.status}, expected captured`);
        }
    }
    catch (err) {
        if (err instanceof functions.https.HttpsError)
            throw err;
        console.error("Razorpay verification error:", err);
        throw new functions.https.HttpsError("internal", "Could not verify payment");
    }
    // If plan/cycle not provided (redirect flow), look up from subscription
    if ((!plan || !cycle) && razorpaySubscriptionId) {
        try {
            const subRes = await fetch(`https://api.razorpay.com/v1/subscriptions/${razorpaySubscriptionId}`, { headers: { Authorization: `Basic ${auth}` } });
            if (subRes.ok) {
                const sub = await subRes.json();
                plan = ((_a = sub.notes) === null || _a === void 0 ? void 0 : _a.plan) || plan;
                cycle = ((_b = sub.notes) === null || _b === void 0 ? void 0 : _b.cycle) || cycle;
            }
        }
        catch (err) {
            console.warn("Could not fetch subscription details:", err);
        }
    }
    // If still no plan/cycle, try Firestore razorpay_subscriptions mapping
    if ((!plan || !cycle) && razorpaySubscriptionId) {
        const db = admin.firestore();
        const subDoc = await db.collection("razorpay_subscriptions").doc(razorpaySubscriptionId).get();
        if (subDoc.exists) {
            const subData = subDoc.data();
            plan = plan || (subData === null || subData === void 0 ? void 0 : subData.plan);
            cycle = cycle || (subData === null || subData === void 0 ? void 0 : subData.cycle);
        }
    }
    if (!plan || !cycle) {
        throw new functions.https.HttpsError("invalid-argument", "Could not determine plan/cycle. Please contact support.");
    }
    // Determine plan limits and expiry
    const daysToAdd = cycle === "annual" ? 365 : 30;
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + daysToAdd);
    const billsLimit = plan === "pro" ? 500 : 999999;
    const productsLimit = 999999; // unlimited for both Pro and Business
    const customersLimit = 999999; // unlimited for both Pro and Business
    const db = admin.firestore();
    // Update user document
    await db.collection("users").doc(userId).update(Object.assign(Object.assign({ "subscription.plan": plan, "subscription.status": "active", "subscription.startedAt": admin.firestore.FieldValue.serverTimestamp(), "subscription.expiresAt": admin.firestore.Timestamp.fromDate(expiresAt) }, (razorpaySubscriptionId && {
        "subscription.razorpaySubscriptionId": razorpaySubscriptionId,
    })), { "limits.billsLimit": billsLimit, "limits.productsLimit": productsLimit, "limits.customersLimit": customersLimit }));
    // Store subscription→user mapping for webhook lookups
    if (razorpaySubscriptionId) {
        await db.collection("razorpay_subscriptions").doc(razorpaySubscriptionId).set({
            userId,
            plan,
            cycle,
            status: "active",
            razorpayPaymentId,
            activatedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
        }, { merge: true });
    }
    // Welcome notification
    await db.collection("users").doc(userId)
        .collection("notifications").add({
        title: `Welcome to ${plan === "pro" ? "Pro" : "Business"} Plan! 🎉`,
        body: `Your ${plan === "pro" ? "Pro" : "Business"} plan is now active. Enjoy ${plan === "pro" ? "500 bills/month" : "unlimited billing"}!`,
        type: "subscription",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ activateSubscription: user ${userId} activated ${plan} (${cycle}), expires ${expiresAt.toISOString()}`);
    return {
        success: true,
        plan,
        cycle,
        expiresAt: expiresAt.toISOString(),
        billsLimit,
        productsLimit,
    };
});
/**
 * Subscription Expiry Reminder — runs daily at 10 AM IST (4:30 UTC).
 * Sends reminder to users whose subscription expires within 7 days.
 * Respects user's settings.subscriptionAlerts preference.
 */
exports.checkSubscriptionExpiry = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 300, memory: "256MB" })
    .pubsub.schedule("30 4 * * *") // 4:30 UTC = 10 AM IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const dateStr = todayStart.toISOString().split("T")[0];
    console.log("📋 Checking subscription expiry (4-touchpoint)...");
    // ── Touch-points (days relative to expiresAt) ──
    const TOUCHPOINTS = [-7, -3, -1, 0, 3];
    // Paginate active subscriptions expiring within the next 7 days
    const sevenDaysLater = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    const fourDaysAgo = new Date(now.getTime() - 4 * 24 * 60 * 60 * 1000);
    const PAGE_SIZE = 200;
    let sentCount = 0;
    let batch = db.batch();
    let batchCount = 0;
    // Helper to process a batch of user docs
    const processUsers = async (docs) => {
        var _a, _b, _c;
        for (const userDoc of docs) {
            const data = userDoc.data();
            if ((data.settings || {}).subscriptionAlerts === false)
                continue;
            const expiresAt = (_b = (_a = data.subscription) === null || _a === void 0 ? void 0 : _a.expiresAt) === null || _b === void 0 ? void 0 : _b.toDate();
            if (!expiresAt)
                continue;
            const daysOffset = Math.round((expiresAt.getTime() - todayStart.getTime()) / (24 * 60 * 60 * 1000));
            if (!TOUCHPOINTS.includes(daysOffset))
                continue;
            const planName = ((_c = data.subscription) === null || _c === void 0 ? void 0 : _c.plan) || "Pro";
            const planLabel = planName.charAt(0).toUpperCase() + planName.slice(1);
            let title;
            let body;
            if (daysOffset === 3) {
                title = `⚠️ ${planLabel} Plan Expires in 3 Days`;
                body = "3 दिन बाकी — अभी renew करें और अपनी unlimited billing जारी रखें।";
            }
            else if (daysOffset === 1) {
                title = `⏰ ${planLabel} Plan Expires Tomorrow!`;
                body = `Renew now to keep your ${planLabel} features. Don't lose your 500 bills/month!`;
            }
            else if (daysOffset === 0) {
                title = `🔴 ${planLabel} Plan Expires Today`;
                body = "Your plan expires today. Renew in seconds to continue without interruption.";
            }
            else if (daysOffset === -3) {
                title = "You've Moved to the Free Plan";
                body = "Your paid plan expired 3 days ago. You're now on Free (50 bills/month). Tap to upgrade.";
            }
            else {
                title = `📅 ${planLabel} Plan Expires in 7 Days`;
                body = `Your ${planLabel} plan expires on ${expiresAt.toLocaleDateString("en-IN")}. Renew to avoid losing access.`;
            }
            // Deterministic doc ID for dedup — no read-before-write needed
            const notifId = `sub_expiry_d${daysOffset}_${dateStr}`;
            const notifRef = db
                .collection("users")
                .doc(userDoc.id)
                .collection("notifications")
                .doc(notifId);
            batch.set(notifRef, {
                title,
                body,
                type: "reminder",
                targetType: "user",
                targetUserId: userDoc.id,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                sentBy: "system",
                read: false,
                data: {
                    trigger: "subscription_expiry",
                    daysOffset,
                    plan: planName,
                },
            });
            batchCount++;
            sentCount++;
            if (batchCount >= 450) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
        }
    };
    // ── Paginate active users expiring within 7 days ──
    let lastDoc;
    while (true) {
        let query = db
            .collection("users")
            .where("subscription.status", "==", "active")
            .where("subscription.expiresAt", "<=", sevenDaysLater)
            .orderBy("subscription.expiresAt")
            .limit(PAGE_SIZE);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const snap = await query.get();
        if (snap.empty)
            break;
        await processUsers(snap.docs);
        if (snap.size < PAGE_SIZE)
            break;
        lastDoc = snap.docs[snap.docs.length - 1];
    }
    // ── Paginate expired users (within last 4 days) ──
    lastDoc = undefined;
    while (true) {
        let query = db
            .collection("users")
            .where("subscription.status", "in", ["expired", "cancelled"])
            .where("subscription.expiresAt", ">=", fourDaysAgo)
            .where("subscription.expiresAt", "<=", now)
            .orderBy("subscription.expiresAt")
            .limit(PAGE_SIZE);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const snap = await query.get();
        if (snap.empty)
            break;
        await processUsers(snap.docs);
        if (snap.size < PAGE_SIZE)
            break;
        lastDoc = snap.docs[snap.docs.length - 1];
    }
    if (batchCount > 0)
        await batch.commit();
    console.log(`📋 Sent ${sentCount} subscription expiry reminder(s)`);
});
// ─── Churn Detection & Re-engagement ───
/**
 * Runs daily. Detects users inactive for 7 / 14 / 30 days and sends
 * culturally-relevant re-engagement push notifications.
 * Tracks the last message sent in `activity.lastChurnMessageDays` to avoid duplicates.
 */
exports.checkChurnedUsers = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 1 })
    .pubsub.schedule("0 5 * * *") // 5:00 UTC = 10:30 AM IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    var _a, _b, _c, _d;
    const db = admin.firestore();
    const now = new Date();
    const PAGE_SIZE = 200;
    // Touchpoint days — ordered MOST urgent first so we pick the highest applicable
    const CHURN_DAYS = [30, 14, 7];
    const messages = {
        7: {
            title: "आपकी दुकान का इंतजार है! 🏪",
            body: "7 दिनों से कोई bill नहीं बनाया। RetailLite पर वापस आएं और अपना कारोबार बढ़ाएं।",
        },
        14: {
            title: "वापस आएं — 30 दिन Pro plan मुफ्त 🎁",
            body: "14 दिन से आप active नहीं हैं। आज sign in करें और 30 दिन का Pro plan बिल्कुल मुफ्त पाएं।",
        },
        30: {
            title: "We miss you, shopkeeper! 🙏",
            body: "आपकी दुकान 30 दिनों से बंद है RetailLite पर। क्या कोई दिक्कत है? हम मदद करने के लिए यहाँ हैं।",
        },
    };
    console.log("👋 Checking for churned users...");
    let notifsSent = 0;
    let lastDoc = null;
    do {
        let q = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
        if (lastDoc)
            q = q.startAfter(lastDoc);
        const page = await q.get();
        if (page.empty)
            break;
        for (const userDoc of page.docs) {
            const data = userDoc.data();
            // Skip users who haven't completed shop setup
            if (!data.isShopSetupComplete)
                continue;
            // Skip if user opted out of notifications
            if ((data.settings || {}).pushNotifications === false)
                continue;
            // Determine last active date
            const lastActive = (_c = (_b = (_a = data.activity) === null || _a === void 0 ? void 0 : _a.lastActiveAt) === null || _b === void 0 ? void 0 : _b.toDate) === null || _c === void 0 ? void 0 : _c.call(_b);
            if (!lastActive)
                continue;
            const daysSinceActive = Math.floor((now.getTime() - lastActive.getTime()) / (24 * 60 * 60 * 1000));
            // Find the applicable touchpoint
            const matchedDay = CHURN_DAYS.find((d) => daysSinceActive >= d);
            if (!matchedDay)
                continue; // active in last 7 days — skip
            // Avoid re-sending the same touchpoint
            const lastSentDays = (_d = data.activity) === null || _d === void 0 ? void 0 : _d.lastChurnMessageDays;
            if (lastSentDays !== undefined && lastSentDays <= matchedDay)
                continue;
            const { title, body } = messages[matchedDay];
            // CF10: Collect writes into batch instead of individual operations
            const batch = db.batch();
            const notifRef = db
                .collection("users")
                .doc(userDoc.id)
                .collection("notifications")
                .doc();
            batch.set(notifRef, {
                title,
                body,
                type: "reminder",
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                sentBy: "system",
                data: { trigger: "churn_reengagement", daysSinceActive, touchpointDays: matchedDay },
            });
            batch.update(db.collection("users").doc(userDoc.id), {
                "activity.lastChurnMessageDays": matchedDay,
            });
            await batch.commit();
            notifsSent++;
        }
        lastDoc = page.docs[page.docs.length - 1];
    } while (true);
    console.log(`👋 Sent ${notifsSent} churn re-engagement notification(s)`);
});
/**
 * Daily Sales Summary — runs daily at 9 PM IST (15:30 UTC).
 * Sends summary of today's sales to each user.
 * Respects user's settings.dailySummary preference.
 */
exports.sendDailySalesSummary = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .pubsub.schedule("30 15 * * *") // 15:30 UTC = 9 PM IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    var _a;
    const db = admin.firestore();
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
    const dateStr = todayStart.toISOString().split("T")[0];
    console.log("📊 Generating daily sales summaries...");
    // ── Step 1: Single collectionGroup query for all bills today ──
    const billsByUser = new Map();
    let lastBillDoc;
    const BILL_PAGE = 5000;
    while (true) {
        let billQuery = db
            .collectionGroup("bills")
            .where("createdAt", ">=", todayStart)
            .where("createdAt", "<", todayEnd)
            .orderBy("createdAt")
            .limit(BILL_PAGE);
        if (lastBillDoc)
            billQuery = billQuery.startAfter(lastBillDoc);
        const billPage = await billQuery.get();
        if (billPage.empty)
            break;
        for (const billDoc of billPage.docs) {
            // Extract userId from path: users/{uid}/bills/{billId}
            const userId = (_a = billDoc.ref.parent.parent) === null || _a === void 0 ? void 0 : _a.id;
            if (!userId)
                continue;
            const existing = billsByUser.get(userId) || { count: 0, revenue: 0 };
            existing.count++;
            existing.revenue += billDoc.data().total || 0;
            billsByUser.set(userId, existing);
        }
        if (billPage.size < BILL_PAGE)
            break;
        lastBillDoc = billPage.docs[billPage.docs.length - 1];
    }
    console.log(`📊 Found bills for ${billsByUser.size} user(s) today`);
    // ── Step 2: Paginate users and write notifications in batches ──
    const PAGE_SIZE = 200;
    let lastDoc;
    let sentCount = 0;
    let batch = db.batch();
    let batchCount = 0;
    while (true) {
        let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const usersSnapshot = await query.get();
        if (usersSnapshot.empty)
            break;
        for (const userDoc of usersSnapshot.docs) {
            const settings = userDoc.data().settings || {};
            if (settings.dailySummary === false)
                continue;
            const stats = billsByUser.get(userDoc.id);
            if (!stats || stats.count === 0)
                continue;
            const title = "Daily Sales Summary 📊";
            const body = `Today: ${stats.count} bill(s) totaling ₹${stats.revenue.toFixed(2)}. Keep up the great work!`;
            const notifRef = db
                .collection("users")
                .doc(userDoc.id)
                .collection("notifications")
                .doc(); // auto-ID
            batch.set(notifRef, {
                title,
                body,
                type: "system",
                targetType: "user",
                targetUserId: userDoc.id,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                sentBy: "system",
                read: false,
                data: {
                    trigger: "daily_summary",
                    totalBills: stats.count,
                    totalRevenue: stats.revenue,
                    date: dateStr,
                },
            });
            batchCount++;
            sentCount++;
            if (batchCount >= 450) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
        }
        if (usersSnapshot.size < PAGE_SIZE)
            break;
        lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
    }
    if (batchCount > 0)
        await batch.commit();
    console.log(`📊 Sent ${sentCount} daily sales summary(ies)`);
});
// ─── Scheduled Firestore Backup ───
/**
 * Daily automated Firestore export at 2 AM IST (20:30 UTC).
 * Exports all collections to Google Cloud Storage for disaster recovery.
 *
 * Prerequisites:
 *   1. Create a GCS bucket: gsutil mb gs://YOUR_PROJECT_ID-backups
 *   2. Grant the default service account the "Cloud Datastore Import Export Admin" role
 *      and "Storage Admin" on the backup bucket:
 *        gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
 *          --member=serviceAccount:YOUR_PROJECT_ID@appspot.gserviceaccount.com \
 *          --role=roles/datastore.importExportAdmin
 *        gsutil iam ch serviceAccount:YOUR_PROJECT_ID@appspot.gserviceaccount.com:admin \
 *          gs://YOUR_PROJECT_ID-backups
 */
// T0-2 FIX: Removed duplicate scheduledFirestoreBackup (REST API version).
// The FirestoreAdminClient version at the bottom of this file is kept —
// it's cleaner, logs to _admin/last_backup, and has proper error handling.
// ─── Windows Desktop Email/Password Auth ───
/**
 * Exchange a Firebase Auth REST API idToken for a custom token.
 *
 * On Windows desktop, signInWithEmailAndPassword fails with unknown-error
 * due to a buggy platform channel. The workaround:
 * 1. Desktop calls Firebase Auth REST API to verify email/password
 * 2. REST API returns an idToken
 * 3. Desktop calls this function to exchange idToken for customToken
 * 4. Desktop calls signInWithCustomToken(customToken) to establish session
 *
 * No auth required since the user isn't signed in yet on desktop.
 */
exports.exchangeIdToken = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data) => {
    const { idToken } = data;
    if (!idToken) {
        throw new functions.https.HttpsError("invalid-argument", "idToken is required");
    }
    try {
        // Verify the idToken to get the user's UID
        const decodedToken = await admin.auth().verifyIdToken(idToken);
        const uid = decodedToken.uid;
        console.log(`🖥️ Exchanging idToken for customToken, uid: ${uid}`);
        // Generate a custom token for this user
        const customToken = await admin.auth().createCustomToken(uid);
        return { customToken };
    }
    catch (error) {
        console.error("❌ exchangeIdToken error:", error);
        throw new functions.https.HttpsError("internal", "Failed to exchange token. Please try again.");
    }
});
// ─── Monthly Business Report ───
/**
 * Runs on the 1st of every month at 9 AM IST.
 * For each user, aggregates last month's bills and sends a summary notification.
 * Iterates users in pages of 200 to avoid timeout at scale.
 */
exports.generateMonthlyReport = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 1 })
    .pubsub.schedule("0 3 1 * *") // 3:30 UTC = 9 AM IST on 1st of month
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    var _a, _b;
    const db = admin.firestore();
    const now = new Date();
    // Compute last month's date range
    const firstOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const firstOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const monthLabel = firstOfLastMonth.toLocaleDateString("en-IN", { month: "long", year: "numeric" });
    const monthKey = `monthly_${firstOfLastMonth.getFullYear()}_${String(firstOfLastMonth.getMonth() + 1).padStart(2, "0")}`;
    console.log(`📊 Generating monthly reports for ${monthLabel}…`);
    // ── Step 1: Single collectionGroup query for all bills last month ──
    const billsByUser = new Map();
    let lastBillDoc;
    const BILL_PAGE = 5000;
    while (true) {
        let billQuery = db
            .collectionGroup("bills")
            .where("createdAt", ">=", firstOfLastMonth)
            .where("createdAt", "<", firstOfThisMonth)
            .orderBy("createdAt")
            .limit(BILL_PAGE);
        if (lastBillDoc)
            billQuery = billQuery.startAfter(lastBillDoc);
        const billPage = await billQuery.get();
        if (billPage.empty)
            break;
        for (const billDoc of billPage.docs) {
            const userId = (_a = billDoc.ref.parent.parent) === null || _a === void 0 ? void 0 : _a.id;
            if (!userId)
                continue;
            const existing = billsByUser.get(userId) || { count: 0, revenue: 0 };
            existing.count++;
            existing.revenue += (_b = billDoc.data().total) !== null && _b !== void 0 ? _b : 0;
            billsByUser.set(userId, existing);
        }
        if (billPage.size < BILL_PAGE)
            break;
        lastBillDoc = billPage.docs[billPage.docs.length - 1];
    }
    console.log(`📊 Found monthly bill data for ${billsByUser.size} user(s)`);
    // ── Step 2: Paginate users, write report + notification in batches ──
    let usersProcessed = 0;
    let lastDoc = null;
    const PAGE_SIZE = 200;
    let batch = db.batch();
    let batchCount = 0;
    do {
        let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const page = await query.get();
        if (page.empty)
            break;
        for (const userDoc of page.docs) {
            const userId = userDoc.id;
            const stats = billsByUser.get(userId);
            if (!stats || stats.count === 0)
                continue;
            const shopName = userDoc.data().shopName || "your shop";
            // Report doc (deterministic ID — idempotent)
            const reportRef = db
                .collection("users")
                .doc(userId)
                .collection("reports")
                .doc(monthKey);
            batch.set(reportRef, {
                type: "monthly",
                month: monthLabel,
                billsCount: stats.count,
                totalRevenue: stats.revenue,
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            batchCount++;
            // Notification doc
            const notifRef = db
                .collection("users")
                .doc(userId)
                .collection("notifications")
                .doc(); // auto-ID
            batch.set(notifRef, {
                title: `📊 ${monthLabel} Report Ready`,
                body: `${shopName} made ${stats.count} bills totalling ₹${stats.revenue.toLocaleString("en-IN")} last month. Tap to view your report.`,
                type: "report",
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                data: { trigger: "monthly_report" },
            });
            batchCount++;
            if (batchCount >= 450) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
            usersProcessed++;
        }
        lastDoc = page.docs[page.docs.length - 1];
    } while (true);
    if (batchCount > 0)
        await batch.commit();
    console.log(`✅ Monthly reports sent to ${usersProcessed} active users`);
});
// ─── Admin Stats Aggregation ───
/**
 * Firestore trigger: updates the aggregated stats document at
 * app_config/stats whenever a user's subscription field changes.
 *
 * This replaces the full-collection scan in AdminFirestoreService.getAdminStats()
 * with a single document read on the admin dashboard.
 *
 * Stats document schema:
 *   { totalUsers, freeUsers, proUsers, businessUsers, mrr, updatedAt }
 */
exports.onSubscriptionWrite = functions
    .region("asia-south1")
    .firestore.document("users/{userId}")
    .onWrite(async (change, context) => {
    var _a, _b, _c, _d, _e, _f;
    // Idempotency guard — prevent counter drift on retries
    const eventId = context.eventId;
    const db = admin.firestore();
    const dedupRef = db.collection("_dedup").doc(eventId);
    const dedupDoc = await dedupRef.get();
    if (dedupDoc.exists) {
        console.log(`⏩ Skipping duplicate event ${eventId}`);
        return;
    }
    await dedupRef.set({ processedAt: admin.firestore.FieldValue.serverTimestamp() });
    const beforePlan = (_c = (_b = (_a = change.before.data()) === null || _a === void 0 ? void 0 : _a.subscription) === null || _b === void 0 ? void 0 : _b.plan) !== null && _c !== void 0 ? _c : "free";
    const afterPlan = (_f = (_e = (_d = change.after.data()) === null || _d === void 0 ? void 0 : _d.subscription) === null || _e === void 0 ? void 0 : _e.plan) !== null && _f !== void 0 ? _f : "free";
    // Only act when plan changed or user was created/deleted
    const userCreated = !change.before.exists && change.after.exists;
    const userDeleted = change.before.exists && !change.after.exists;
    const planChanged = beforePlan !== afterPlan;
    if (!userCreated && !userDeleted && !planChanged)
        return;
    // db already declared above (L1715) — reuse it
    const statsRef = db.collection("app_config").doc("stats");
    await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
        // Increment/decrement counts
        const delta = {};
        if (userCreated) {
            delta.totalUsers = admin.firestore.FieldValue.increment(1);
            delta[`${afterPlan}Users`] = admin.firestore.FieldValue.increment(1);
        }
        else if (userDeleted) {
            delta.totalUsers = admin.firestore.FieldValue.increment(-1);
            delta[`${beforePlan}Users`] = admin.firestore.FieldValue.increment(-1);
        }
        else if (planChanged) {
            delta[`${beforePlan}Users`] = admin.firestore.FieldValue.increment(-1);
            delta[`${afterPlan}Users`] = admin.firestore.FieldValue.increment(1);
        }
        // Recompute MRR delta: subscription price only when plan is active
        const mrrMap = { free: 0, pro: 299, business: 999 };
        const mrrBefore = change.before.exists
            && ((_b = (_a = change.before.data()) === null || _a === void 0 ? void 0 : _a.subscription) === null || _b === void 0 ? void 0 : _b.status) === "active"
            ? ((_c = mrrMap[beforePlan]) !== null && _c !== void 0 ? _c : 0) : 0;
        const mrrAfter = change.after.exists
            && ((_e = (_d = change.after.data()) === null || _d === void 0 ? void 0 : _d.subscription) === null || _e === void 0 ? void 0 : _e.status) === "active"
            ? ((_f = mrrMap[afterPlan]) !== null && _f !== void 0 ? _f : 0) : 0;
        if (mrrAfter !== mrrBefore) {
            delta.mrr = admin.firestore.FieldValue.increment(mrrAfter - mrrBefore);
        }
        delta.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        // D1-1: Also aggregate platform and feature usage counts
        if (userCreated || userDeleted) {
            const userData = userCreated ? change.after.data() : change.before.data();
            const platform = ((_h = (_g = userData === null || userData === void 0 ? void 0 : userData.activity) === null || _g === void 0 ? void 0 : _g.platform) !== null && _h !== void 0 ? _h : "unknown").toLowerCase();
            const inc = userCreated ? 1 : -1;
            delta[`platformCounts.${platform}`] = admin.firestore.FieldValue.increment(inc);
            // Feature usage: check limits for billing/products/customers activity
            const limits = (_j = userData === null || userData === void 0 ? void 0 : userData.limits) !== null && _j !== void 0 ? _j : {};
            if (((_k = limits.billsThisMonth) !== null && _k !== void 0 ? _k : 0) > 0) {
                delta["featureUsageCounts.billing"] = admin.firestore.FieldValue.increment(inc);
            }
            if (((_l = limits.productsCount) !== null && _l !== void 0 ? _l : 0) > 0) {
                delta["featureUsageCounts.products"] = admin.firestore.FieldValue.increment(inc);
            }
            if (((_m = limits.customersCount) !== null && _m !== void 0 ? _m : 0) > 0) {
                delta["featureUsageCounts.khata"] = admin.firestore.FieldValue.increment(inc);
            }
        }
        tx.set(statsRef, delta, { merge: true });
    });
    console.log(`📈 Stats updated: ${beforePlan}→${afterPlan} for user ${context.params.userId}`);
});
// ─── Referral Program ───────────────────────────────────────────────────────
/**
 * Stores the referrer's UID on the caller's user doc so processReferralReward
 * can credit them when the referee first subscribes.
 */
exports.redeemReferralCode = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 20 })
    .https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login required");
    }
    const code = String(data.code || "").toUpperCase().trim();
    if (code.length !== 8) {
        throw new functions.https.HttpsError("invalid-argument", "Code must be 8 characters");
    }
    const db = admin.firestore();
    const uid = context.auth.uid;
    const userDoc = await db.collection("users").doc(uid).get();
    if ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.referredBy) {
        throw new functions.https.HttpsError("already-exists", "You have already applied a referral code");
    }
    const referrerSnap = await db.collection("users")
        .where("referralCode", "==", code)
        .limit(1)
        .get();
    if (referrerSnap.empty) {
        throw new functions.https.HttpsError("not-found", "Invalid referral code");
    }
    const referrerId = referrerSnap.docs[0].id;
    if (referrerId === uid) {
        throw new functions.https.HttpsError("invalid-argument", "You cannot use your own referral code");
    }
    await db.collection("users").doc(uid).update({
        referredBy: referrerId,
        referralCodeUsed: code,
        referralCodeAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`🎁 Referral code ${code} redeemed by ${uid} (referrer: ${referrerId})`);
    return { success: true };
});
/**
 * Fires when a new subscription is created. If the subscriber was referred by
 * someone, extends the referrer's subscription by 30 days (first subscribe only).
 */
exports.processReferralReward = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 20 })
    .firestore.document("razorpay_subscriptions/{subId}")
    .onCreate(async (snapshot) => {
    var _a, _b, _c, _d, _e;
    const subscriptionData = snapshot.data();
    const userId = subscriptionData === null || subscriptionData === void 0 ? void 0 : subscriptionData.userId;
    if (!userId)
        return;
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();
    const referrerId = (_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.referredBy;
    if (!referrerId)
        return;
    // Only reward once per referee
    const existing = await db.collection("referral_rewards")
        .where("refereeId", "==", userId)
        .limit(1)
        .get();
    if (!existing.empty) {
        console.log(`🔁 Referral reward already issued for referee ${userId}`);
        return;
    }
    // Extend referrer subscription by 30 days
    const referrerDoc = await db.collection("users").doc(referrerId).get();
    const currentExpiry = (_c = (_b = referrerDoc.data()) === null || _b === void 0 ? void 0 : _b.subscription) === null || _c === void 0 ? void 0 : _c.expiresAt;
    const baseDate = currentExpiry
        ? new Date(Math.max(currentExpiry.toDate().getTime(), Date.now()))
        : new Date();
    const newExpiry = new Date(baseDate.getTime() + 30 * 24 * 60 * 60 * 1000);
    // Extend referee (subscriber) subscription by 30 days too
    const refereeSub = (_e = (_d = userDoc.data()) === null || _d === void 0 ? void 0 : _d.subscription) === null || _e === void 0 ? void 0 : _e.expiresAt;
    const refereeBase = refereeSub
        ? new Date(Math.max(refereeSub.toDate().getTime(), Date.now()))
        : new Date();
    const refereeNewExpiry = new Date(refereeBase.getTime() + 30 * 24 * 60 * 60 * 1000);
    const batch = db.batch();
    // Update referrer
    batch.update(db.collection("users").doc(referrerId), {
        "subscription.expiresAt": admin.firestore.Timestamp.fromDate(newExpiry),
    });
    // Update referee
    batch.update(db.collection("users").doc(userId), {
        "subscription.expiresAt": admin.firestore.Timestamp.fromDate(refereeNewExpiry),
    });
    // Audit trail
    const rewardRef = db.collection("referral_rewards").doc();
    batch.set(rewardRef, {
        referrerId,
        refereeId: userId,
        rewardDays: 30,
        bothRewarded: true,
        rewardedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // In-app notification for referrer
    const notifRef = db.collection("users").doc(referrerId).collection("notifications").doc();
    batch.set(notifRef, {
        title: "🎁 Referral Reward! +30 Days Free",
        body: "Your friend just upgraded! You both get 30 extra days of Pro.",
        type: "referral",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // In-app notification for referee
    const refereeNotifRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(refereeNotifRef, {
        title: "🎁 Welcome Bonus! +30 Days Free",
        body: "Thanks for using a referral code! You got 30 extra days of Pro.",
        type: "referral",
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    console.log(`🎁 Referral reward granted: both ${referrerId} and ${userId} get +30 days`);
});
// ═══════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION LIMIT ENFORCEMENT (Server-side safety nets)
// ═══════════════════════════════════════════════════════════════════════════════
/**
 * onBillCreated — After a bill is created, increment billsThisMonth counter.
 * Also validates the limit and deletes the bill if over-limit (safety net
 * in case the Firestore security rule check is bypassed via Admin SDK or
 * a race condition).
 */
exports.onBillCreated = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/bills/{billId}")
    .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const userId = context.params.userId;
    const billId = context.params.billId;
    const userRef = db.collection("users").doc(userId);
    try {
        await db.runTransaction(async (txn) => {
            const userDoc = await txn.get(userRef);
            if (!userDoc.exists)
                return;
            const data = userDoc.data();
            const limits = data.limits || {};
            const now = new Date();
            const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
            // Detect month rollover
            const lastResetMonth = limits.lastResetMonth || "";
            const isNewMonth = lastResetMonth !== currentMonth;
            const billsThisMonth = isNewMonth ? 0 : (limits.billsThisMonth || 0);
            const billsLimit = limits.billsLimit || 50;
            if (billsThisMonth >= billsLimit) {
                // Over limit — delete the bill (safety net)
                console.warn(`⚠️ onBillCreated: User ${userId} OVER bill limit (${billsThisMonth}/${billsLimit}). Deleting bill ${billId}.`);
                txn.delete(snap.ref);
                return;
            }
            // Increment counter + update rate-limit timestamp
            txn.update(userRef, {
                "limits.billsThisMonth": billsThisMonth + 1,
                "limits.lastResetMonth": currentMonth,
                "_lastWriteAt": admin.firestore.FieldValue.serverTimestamp(),
            });
        });
    }
    catch (e) {
        console.error(`❌ onBillCreated: Failed for user ${userId}, bill ${billId}:`, e);
    }
});
/**
 * onProductCreated — After a product is created, increment productsCount.
 * Validates limit and deletes if over (safety net).
 */
exports.onProductCreated = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/products/{productId}")
    .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const userId = context.params.userId;
    const productId = context.params.productId;
    const userRef = db.collection("users").doc(userId);
    try {
        await db.runTransaction(async (txn) => {
            const userDoc = await txn.get(userRef);
            if (!userDoc.exists)
                return;
            const data = userDoc.data();
            const limits = data.limits || {};
            const productsCount = limits.productsCount || 0;
            const productsLimit = limits.productsLimit || 100;
            if (productsCount >= productsLimit) {
                console.warn(`⚠️ onProductCreated: User ${userId} OVER product limit (${productsCount}/${productsLimit}). Deleting product ${productId}.`);
                txn.delete(snap.ref);
                return;
            }
            txn.update(userRef, {
                "limits.productsCount": productsCount + 1,
            });
        });
    }
    catch (e) {
        console.error(`❌ onProductCreated: Failed for user ${userId}, product ${productId}:`, e);
    }
});
/**
 * onProductDeleted — Decrement productsCount when a product is deleted.
 */
exports.onProductDeleted = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/products/{productId}")
    .onDelete(async (_snap, context) => {
    const db = admin.firestore();
    const userId = context.params.userId;
    const userRef = db.collection("users").doc(userId);
    try {
        await userRef.update({
            "limits.productsCount": admin.firestore.FieldValue.increment(-1),
        });
    }
    catch (e) {
        console.error(`❌ onProductDeleted: Failed for user ${userId}:`, e);
    }
});
/**
 * onCustomerCreated — After a customer is created, increment customersCount.
 * Validates limit and deletes if over (safety net — mirrors onProductCreated).
 */
exports.onCustomerCreated = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/customers/{customerId}")
    .onCreate(async (snap, context) => {
    const db = admin.firestore();
    const userId = context.params.userId;
    const customerId = context.params.customerId;
    const userRef = db.collection("users").doc(userId);
    try {
        await db.runTransaction(async (txn) => {
            const userDoc = await txn.get(userRef);
            if (!userDoc.exists)
                return;
            const data = userDoc.data();
            const limits = data.limits || {};
            const customersCount = limits.customersCount || 0;
            const customersLimit = limits.customersLimit || 10;
            if (customersCount >= customersLimit) {
                console.warn(`⚠️ onCustomerCreated: User ${userId} OVER customer limit (${customersCount}/${customersLimit}). Deleting customer ${customerId}.`);
                txn.delete(snap.ref);
                return;
            }
            txn.update(userRef, {
                "limits.customersCount": customersCount + 1,
            });
        });
    }
    catch (e) {
        console.error(`❌ onCustomerCreated: Failed for user ${userId}, customer ${customerId}:`, e);
    }
});
/**
 * onCustomerDeleted — Decrement customersCount when a customer is deleted.
 */
exports.onCustomerDeleted = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/customers/{customerId}")
    .onDelete(async (_snap, context) => {
    const db = admin.firestore();
    const userId = context.params.userId;
    const userRef = db.collection("users").doc(userId);
    try {
        await userRef.update({
            "limits.customersCount": admin.firestore.FieldValue.increment(-1),
        });
    }
    catch (e) {
        console.error(`❌ onCustomerDeleted: Failed for user ${userId}:`, e);
    }
});
/**
 * seedAdmins — One-time callable to populate the /admins collection
 * from the hardcoded list. Run once after deploying the new rules.
 * Can be called by any existing admin (validated via old hardcoded list
 * or new collection).
 */
exports.seedAdmins = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, maxInstances: 1 })
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    const adminEmailsEnv = process.env.ADMIN_EMAILS || "";
    const adminEmails = adminEmailsEnv
        ? adminEmailsEnv.split(",").map(e => e.trim()).filter(e => e.length > 0)
        : [
            "kehsaram001@gmail.com",
            "admin@retaillite.com",
            "bharathiinstitute1@gmail.com",
            "bharahiinstitute1@gmail.com",
            "shivamsingh8556@gmail.com",
            "admin@lite.app",
            "kehsihba@gmail.com",
        ];
    // Only allow existing admins to seed
    if (!adminEmails.includes(context.auth.token.email || "")) {
        throw new functions.https.HttpsError("permission-denied", "Not an admin");
    }
    const db = admin.firestore();
    const batch = db.batch();
    for (const email of adminEmails) {
        batch.set(db.collection("admins").doc(email), {
            email,
            addedAt: admin.firestore.FieldValue.serverTimestamp(),
            addedBy: context.auth.uid,
        });
    }
    await batch.commit();
    console.log(`✅ seedAdmins: ${adminEmails.length} admin emails seeded`);
    return { success: true, count: adminEmails.length };
});
/**
 * getSubscriptionLimits — Callable function for clients to get
 * authoritative subscription limits (prevents client spoofing).
 */
exports.getSubscriptionLimits = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, maxInstances: 50 })
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    const userId = context.auth.uid;
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
        return {
            billsThisMonth: 0,
            billsLimit: 50,
            productsCount: 0,
            productsLimit: 100,
            customersCount: 0,
            plan: "free",
            status: "active",
        };
    }
    const data = userDoc.data();
    const limits = data.limits || {};
    const sub = data.subscription || {};
    return {
        billsThisMonth: limits.billsThisMonth || 0,
        billsLimit: limits.billsLimit || 50,
        productsCount: limits.productsCount || 0,
        productsLimit: limits.productsLimit || 100,
        customersCount: limits.customersCount || 0,
        plan: sub.plan || "free",
        status: sub.status || "active",
    };
});
// ═══════════════════════════════════════════════════════
// D1-2: SERVER-SIDE NOTIFICATION FAN-OUT
// Replaces client-side full-collection scans with paginated
// server-side writes (200 users per page, 500 writes per batch)
// ═══════════════════════════════════════════════════════
/**
 * Send a notification to ALL users. Paginates users server-side
 * to avoid loading 10K+ user docs on the client.
 */
exports.sendNotificationToAll = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 5 })
    .https.onCall(async (data, context) => {
    // Only admins can broadcast
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    const db = admin.firestore();
    const callerEmail = context.auth.token.email || "";
    const adminDoc = await db.collection("admins").doc(callerEmail).get();
    if (!adminDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
    const { title, body, type, sentBy } = data;
    if (!title || !body) {
        throw new functions.https.HttpsError("invalid-argument", "title and body are required");
    }
    // Save to global notifications collection
    const globalRef = await db.collection("notifications").add(Object.assign({ title, body, type: type || "announcement", targetType: "all", sentBy: sentBy || "system", createdAt: admin.firestore.FieldValue.serverTimestamp() }, (data.data ? { data: data.data } : {})));
    let totalCount = 0;
    let lastDoc;
    // Paginate users 200 at a time
    while (true) {
        let query = db.collection("users").orderBy("__name__").limit(200);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const page = await query.get();
        if (page.empty)
            break;
        let batch = db.batch();
        let batchCount = 0;
        for (const userDoc of page.docs) {
            const notifRef = db
                .collection("users").doc(userDoc.id)
                .collection("notifications").doc();
            batch.set(notifRef, Object.assign({ title, body, type: type || "announcement", targetType: "all", sentBy: sentBy || "system", read: false, readAt: null, createdAt: admin.firestore.FieldValue.serverTimestamp(), globalNotificationId: globalRef.id }, (data.data ? { data: data.data } : {})));
            batchCount++;
            totalCount++;
            if (batchCount >= 500) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
        }
        if (batchCount > 0)
            await batch.commit();
        lastDoc = page.docs[page.docs.length - 1];
    }
    await globalRef.update({
        recipientCount: totalCount,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`📨 Notification sent to ${totalCount} users`);
    return { success: true, recipientCount: totalCount };
});
/**
 * Send a notification to users with a specific subscription plan.
 * Paginates server-side.
 */
exports.sendNotificationToPlan = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 5 })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    const db = admin.firestore();
    const callerEmail = context.auth.token.email || "";
    const adminDoc = await db.collection("admins").doc(callerEmail).get();
    if (!adminDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
    const { plan, title, body, type, sentBy } = data;
    if (!plan || !title || !body) {
        throw new functions.https.HttpsError("invalid-argument", "plan, title, and body required");
    }
    const globalRef = await db.collection("notifications").add(Object.assign({ title, body, type: type || "announcement", targetType: "plan", targetPlan: plan, sentBy: sentBy || "system", createdAt: admin.firestore.FieldValue.serverTimestamp() }, (data.data ? { data: data.data } : {})));
    let totalCount = 0;
    let lastDoc;
    while (true) {
        let query = db.collection("users")
            .where("subscription.plan", "==", plan)
            .orderBy("__name__").limit(200);
        if (lastDoc)
            query = query.startAfter(lastDoc);
        const page = await query.get();
        if (page.empty)
            break;
        let batch = db.batch();
        let batchCount = 0;
        for (const userDoc of page.docs) {
            const notifRef = db
                .collection("users").doc(userDoc.id)
                .collection("notifications").doc();
            batch.set(notifRef, Object.assign({ title, body, type: type || "announcement", targetType: "plan", targetPlan: plan, sentBy: sentBy || "system", read: false, readAt: null, createdAt: admin.firestore.FieldValue.serverTimestamp(), globalNotificationId: globalRef.id }, (data.data ? { data: data.data } : {})));
            batchCount++;
            totalCount++;
            if (batchCount >= 500) {
                await batch.commit();
                batch = db.batch();
                batchCount = 0;
            }
        }
        if (batchCount > 0)
            await batch.commit();
        lastDoc = page.docs[page.docs.length - 1];
    }
    await globalRef.update({
        recipientCount: totalCount,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`📨 Notification sent to ${totalCount} ${plan} users`);
    return { success: true, recipientCount: totalCount };
});
// ═══════════════════════════════════════════════════════
// SCHEDULED FIRESTORE BACKUP
// Runs daily at 2:00 AM IST (20:30 UTC previous day)
// Exports entire Firestore database to Cloud Storage
// ═══════════════════════════════════════════════════════
// Lazy-initialize to avoid module-load crashes in emulator/testing environments
let _firestoreClient = null;
function getFirestoreClient() {
    if (!_firestoreClient) {
        _firestoreClient = new admin.firestore.v1.FirestoreAdminClient();
    }
    return _firestoreClient;
}
exports.scheduledFirestoreBackup = functions
    .region("asia-south1")
    .pubsub.schedule("30 20 * * *") // 2:00 AM IST = 20:30 UTC
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
    const projectId = process.env.GCP_PROJECT || process.env.GCLOUD_PROJECT || "retaillite";
    const bucket = `gs://${projectId}-firestore-backups`;
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    try {
        const firestoreClient = getFirestoreClient();
        const databaseName = firestoreClient.databasePath(projectId, "(default)");
        const [response] = await firestoreClient.exportDocuments({
            name: databaseName,
            outputUriPrefix: `${bucket}/backups/${timestamp}`,
            // Export all collections
            collectionIds: [],
        });
        console.log(`✅ Firestore backup started: ${response.name}`);
        console.log(`   Output: ${bucket}/backups/${timestamp}`);
        // Log backup start to admin collection
        await admin.firestore().collection("_admin").doc("last_backup").set({
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            outputPath: `${bucket}/backups/${timestamp}`,
            operationName: response.name,
            status: "started",
        });
        // Poll the export operation until it completes (max 8 minutes)
        const operationName = response.name;
        const maxAttempts = 48; // 48 × 10s = 8 minutes
        let completed = false;
        for (let i = 0; i < maxAttempts; i++) {
            await new Promise(resolve => setTimeout(resolve, 10000)); // wait 10s
            try {
                const operation = await firestoreClient.checkExportDocumentsProgress(operationName);
                const op = Array.isArray(operation) ? operation[0] : operation;
                if (op.done) {
                    completed = true;
                    console.log(`✅ Firestore backup completed: ${operationName}`);
                    await admin.firestore().collection("_admin").doc("last_backup").update({
                        status: "completed",
                        completedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    break;
                }
            }
            catch (pollErr) {
                // checkExportDocumentsProgress may not be available; fall back to marking as started
                console.warn(`⚠️ Could not poll backup status (attempt ${i + 1}):`, pollErr);
                // Don't fail — the export is still running. Just mark as completed optimistically after first poll failure.
                if (i >= 2) {
                    console.log("⚠️ Marking backup as completed (poll unavailable, export was accepted)");
                    await admin.firestore().collection("_admin").doc("last_backup").update({
                        status: "completed",
                        completedAt: admin.firestore.FieldValue.serverTimestamp(),
                        note: "Status inferred — poll API unavailable",
                    });
                    completed = true;
                    break;
                }
            }
        }
        if (!completed) {
            console.warn("⚠️ Backup may still be running (timed out waiting for completion)");
            await admin.firestore().collection("_admin").doc("last_backup").update({
                status: "timeout",
                note: "Export accepted but did not complete within 8 minutes. Check GCS bucket manually.",
            });
        }
        return null;
    }
    catch (e) {
        console.error("❌ Firestore backup failed:", e);
        // Log failure
        await admin.firestore().collection("_admin").doc("last_backup").set({
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            status: "failed",
            error: String(e),
        });
        return null;
    }
});
/**
 * seedUserUsage — Admin-only callable that scans all users and populates
 * the user_usage collection with document counts from their subcollections.
 * This bootstraps the per-user cost tracking with existing data.
 */
exports.seedUserUsage = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 120, memory: "512MB", maxInstances: 1 })
    .https.onCall(async (_data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
    }
    // Verify caller is admin
    const db = admin.firestore();
    const callerEmail = context.auth.token.email || "";
    const adminDoc = await db.collection("admins").doc(callerEmail).get();
    const hardcodedAdmins = [
        "kehsaram001@gmail.com",
        "admin@retaillite.com",
    ];
    if (!adminDoc.exists && !hardcodedAdmins.includes(callerEmail)) {
        throw new functions.https.HttpsError("permission-denied", "Admin access required");
    }
    console.log("🌱 seedUserUsage: Starting...");
    // Get all users
    const usersSnap = await db.collection("users").get();
    let seeded = 0;
    // Get admin emails set for fast lookup
    const adminsSnap = await db.collection("admins").get();
    const adminEmails = new Set([
        ...hardcodedAdmins,
        ...adminsSnap.docs.map(d => d.id.toLowerCase()),
    ]);
    let batch = db.batch();
    const batchLimit = 400;
    let batchCount = 0;
    for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        // Count subcollection documents
        const [billsCount, productsCount, expensesCount, transactionsCount] = await Promise.all([
            db.collection(`users/${userId}/bills`).count().get(),
            db.collection(`users/${userId}/products`).count().get(),
            db.collection(`users/${userId}/expenses`).count().get(),
            db.collection(`users/${userId}/transactions`).count().get(),
        ]);
        const bills = billsCount.data().count;
        const products = productsCount.data().count;
        const expenses = expensesCount.data().count;
        const transactions = transactionsCount.data().count;
        // Estimate usage based on document counts
        const totalDocs = bills + products + expenses + transactions;
        // Each doc was written once and read ~3x on average
        const estimatedReads = totalDocs * 3;
        const estimatedWrites = totalDocs;
        // Average Firestore doc size ~1 KB; storage = docs × 1 KB
        const estimatedStorageBytes = totalDocs * 1024;
        // Each read serves ~1 KB avg doc over network
        const estimatedNetworkBytes = estimatedReads * 1024;
        // Estimate 2 function calls per session, avg 30 sessions per user
        const estimatedFunctionCalls = Math.max(2, Math.round(totalDocs * 0.1));
        // Estimate storage uploads: users with products likely uploaded some images
        // Average product image ~30 KB after resize, logo ~20 KB
        const hasLogo = userData.shopLogo || ((_a = userData.profile) === null || _a === void 0 ? void 0 : _a.shopLogo) ? 1 : 0;
        const estimatedStorageUploadBytes = (products * 30 * 1024) + (hasLogo * 20 * 1024);
        // Downloads ~2x uploads (images displayed multiple times)
        const estimatedStorageDownloadBytes = estimatedStorageUploadBytes * 2;
        const email = userData.email || ((_b = userData.profile) === null || _b === void 0 ? void 0 : _b.email) || "";
        const isAdmin = adminEmails.has(email.toLowerCase());
        // Calculate total estimated cost
        const readsCost = (estimatedReads / 100000) * 0.06;
        const writesCost = (estimatedWrites / 100000) * 0.18;
        const storageCost = (estimatedStorageBytes / (1024 * 1024 * 1024)) * 0.026;
        const networkCost = (estimatedNetworkBytes / (1024 * 1024 * 1024)) * 0.12;
        const functionsCost = (estimatedFunctionCalls / 1000000) * 0.40;
        const fileStorageCost = (estimatedStorageUploadBytes / (1024 * 1024 * 1024)) * 0.026;
        const downloadCost = (estimatedStorageDownloadBytes / (1024 * 1024 * 1024)) * 0.12;
        const totalCost = readsCost + writesCost + storageCost + networkCost +
            functionsCost + fileStorageCost + downloadCost;
        const usageRef = db.collection("user_usage").doc(userId);
        batch.set(usageRef, {
            userId: userId,
            email: email,
            isAdmin: isAdmin,
            firestoreReads: estimatedReads,
            firestoreWrites: estimatedWrites,
            firestoreDeletes: 0,
            storageBytes: estimatedStorageBytes,
            functionCalls: estimatedFunctionCalls,
            networkEgressBytes: estimatedNetworkBytes,
            storageUploadBytes: estimatedStorageUploadBytes,
            storageDownloadBytes: estimatedStorageDownloadBytes,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            periodStart: admin.firestore.Timestamp.fromDate(new Date(new Date().getFullYear(), new Date().getMonth(), 1)),
            estimatedCost: totalCost,
            docCounts: { bills, products, expenses, transactions },
        }, { merge: true });
        seeded++;
        batchCount++;
        // Commit in chunks of 400
        if (batchCount >= batchLimit) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
        }
    }
    // Commit remaining
    if (batchCount > 0) {
        await batch.commit();
    }
    console.log(`✅ seedUserUsage: Seeded ${seeded} users`);
    return { success: true, seeded };
});
//# sourceMappingURL=index.js.map