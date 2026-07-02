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

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as nodemailer from "nodemailer";

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

interface PaymentLinkRequest {
    amount: number; // Amount in rupees
    customerName: string;
    customerPhone: string;
    customerEmail?: string;
    description: string;
    billId?: string;
    shopName?: string;
}

interface PaymentLinkResponse {
    success: boolean;
    paymentLink?: string;
    paymentLinkId?: string;
    shortUrl?: string;
    error?: string;
}

/**
 * Create a Razorpay Payment Link
 * 
 * This function creates a shareable payment link that customers can use
 * to pay via UPI, cards, or netbanking.
 */
export const createPaymentLink = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(
        async (data: PaymentLinkRequest, context): Promise<PaymentLinkResponse> => {
            // Verify authentication (optional but recommended)
            if (!context.auth) {
                throw new functions.https.HttpsError(
                    "unauthenticated",
                    "User must be authenticated to create payment links"
                );
            }

            // Validate input
            if (!data.amount || data.amount <= 0) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "Amount must be greater than 0"
                );
            }

            if (!data.customerName || !data.customerPhone) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "Customer name and phone are required"
                );
            }

            const razorpayConfig = getRazorpayConfig();

            // Check if Razorpay is configured
            if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
                console.error("Razorpay not configured:", {
                    hasKeyId: !!razorpayConfig.keyId,
                    hasKeySecret: !!razorpayConfig.keySecret
                });
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Razorpay is not configured. Set razorpay.key_id and razorpay.key_secret"
                );
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

                const result = await response.json() as Record<string, unknown>;

                if (!response.ok) {
                    console.error("Razorpay API error:", result);
                    const errorDesc = (result.error as Record<string, unknown>)?.description as string || "Failed to create payment link";
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
                } catch (dbError) {
                    console.warn("Failed to log payment link:", dbError);
                }

                return {
                    success: true,
                    paymentLink: result.short_url as string,
                    paymentLinkId: result.id as string,
                    shortUrl: result.short_url as string,
                };
            } catch (error) {
                console.error("Error creating payment link:", error);
                return {
                    success: false,
                    error: error instanceof Error ? error.message : "Unknown error",
                };
            }
        }
    );

/**
 * Webhook handler for Razorpay payment status updates
 * 
 * Configure this URL in Razorpay Dashboard -> Settings -> Webhooks
 * IMPORTANT: Set the webhook secret via:
 *   firebase functions:config:set razorpay.webhook_secret="your_webhook_secret"
 */
export const razorpayWebhook = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onRequest(async (req, res) => {
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

            const signature = req.headers["x-razorpay-signature"] as string;
            if (!signature) {
                console.warn("Missing x-razorpay-signature header — rejecting request");
                res.status(401).send("Unauthorized: missing signature");
                return;
            }

            // Compute expected signature: HMAC-SHA256 of raw body with webhook secret
            const rawBody = (req as any).rawBody || (typeof req.body === "string" ? req.body : JSON.stringify(req.body));
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
                    const paymentLinkId = event.payload.payment_link?.entity?.id;
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
                                paymentId: event.payload.payment?.entity?.id,
                            });
                            console.log("Payment link marked as paid:", paymentLinkId);
                        }
                    }
                    break;

                case "payment_link.expired":
                    console.log("Payment link expired");
                    break;

                // ─── One-time payment backup verification ───
                // If the client verifyPayment call fails (e.g. network issue after UPI payment),
                // this webhook acts as a safety net to activate the plan.
                case "order.paid": {
                    const order = event.payload.order?.entity;
                    const payment = event.payload.payment?.entity;
                    if (!order || !payment) break;

                    const orderId = order.id;
                    const notes = order.notes || {};
                    const webhookUserId = notes.userId as string | undefined;
                    const webhookPlan = notes.plan as string | undefined;
                    const webhookCycle = notes.cycle as string | undefined;

                    if (!webhookUserId || !webhookPlan || !webhookCycle) {
                        console.log("order.paid: missing notes, skipping", orderId);
                        break;
                    }

                    // Check if plan is already activated (verifyPayment may have run first)
                    const userDoc = await admin.firestore().collection("users").doc(webhookUserId).get();
                    const currentPaymentId = userDoc.data()?.subscription?.paymentId;
                    if (currentPaymentId === payment.id) {
                        console.log(`order.paid: user ${webhookUserId} already activated with payment ${payment.id}, skipping`);
                        break;
                    }

                    // Activate plan as backup
                    const daysToAdd = webhookCycle === "annual" ? 365 : 30;
                    const expiresAt = new Date();
                    expiresAt.setDate(expiresAt.getDate() + daysToAdd);
                    const billsLimit = webhookPlan === "pro" ? 500 : 999999;

                    await admin.firestore().collection("users").doc(webhookUserId).update({
                        "subscription.plan": webhookPlan,
                        "subscription.status": "active",
                        "subscription.cycle": webhookCycle,
                        "subscription.startedAt": admin.firestore.FieldValue.serverTimestamp(),
                        "subscription.expiresAt": admin.firestore.Timestamp.fromDate(expiresAt),
                        "subscription.orderId": orderId,
                        "subscription.paymentId": payment.id,
                        "limits.billsLimit": billsLimit,
                        "limits.productsLimit": 999999,
                        "limits.customersLimit": 999999,
                    });

                    // Welcome notification
                    await admin.firestore().collection("users").doc(webhookUserId)
                        .collection("notifications").add({
                            title: `Welcome to ${webhookPlan === "pro" ? "Pro" : "Business"} Plan! 🎉`,
                            body: `Your ${webhookPlan === "pro" ? "Pro" : "Business"} plan is now active. Enjoy ${webhookPlan === "pro" ? "500 bills/month" : "unlimited billing"}!`,
                            type: "subscription",
                            read: false,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });

                    console.log(`order.paid (webhook fallback): activated ${webhookPlan} for user ${webhookUserId}`);
                    break;
                }

                default:
                    console.log("Unhandled webhook event:", event.event);
            }

            res.status(200).send("OK");
        } catch (error) {
            console.error("Webhook error:", error);
            res.status(500).send("Internal error");
        }
    });

// ─── Pre-Registration Email OTP ───

/**
 * Send a 6-digit OTP to an email BEFORE account creation
 * No authentication required — used during registration
 */
export const sendRegistrationOTP = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data: { email: string }) => {
        const email = data.email?.trim()?.toLowerCase();

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
            const lastSent = existing.data()?.sentAt?.toDate();
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
        } catch (emailError: any) {
            console.error("Failed to send OTP email:", emailError);
            await otpRef.delete();
            const detail = emailError?.response || emailError?.message || "Unknown error";
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
export const verifyRegistrationOTP = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data: { email: string; otp: string }) => {
        const email = data.email?.trim()?.toLowerCase();
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

        const otpData = otpDoc.data()!;

        // Check max attempts (5 tries)
        if (otpData.attempts >= 5) {
            await otpRef.delete();
            return { success: false, error: "Too many attempts. Please request a new code." };
        }

        // Check expiry
        const expiresAt = otpData.expiresAt?.toDate?.() || new Date(0);
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
async function deleteUserSubcollections(uid: string): Promise<number> {
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
            if (snapshot.empty) { hasMore = false; continue; }
            if (collName === "customers") {
                for (const customerDoc of snapshot.docs) {
                    let innerHasMore = true;
                    while (innerHasMore) {
                        const txnSnap = await customerDoc.ref.collection("transactions").limit(400).get();
                        if (txnSnap.empty) { innerHasMore = false; continue; }
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
export const onUserDeleted = functions
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
                console.log(`🗑️ Deleting Firestore user doc: phone=${data?.phone}, shop=${data?.shopName}`);
                await userDoc.delete();
                console.log(`✅ Firestore user doc deleted for ${email}`);
            } else {
                console.log(`ℹ️ No Firestore user doc found for ${uid}`);
            }
        } catch (error) {
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
export const deleteUserAccount = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 300, memory: "512MB", maxInstances: 20 })
    .https.onCall(async (_data: unknown, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "User must be authenticated to delete their account"
            );
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
            } catch (_) {
                // May not exist
            }

            // 3. Delete user's Storage files (profile images, shop logos)
            try {
                const bucket = admin.storage().bucket();
                await bucket.deleteFiles({ prefix: `users/${uid}/` });
                console.log(`🗑️ Deleted Storage files for ${uid}`);
            } catch (e) {
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
        } catch (error) {
            console.error(`❌ Account deletion failed for ${uid}:`, error);
            throw new functions.https.HttpsError(
                "internal",
                "Failed to delete account. Please try again or contact support."
            );
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
export const generateDesktopToken = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data: { linkCode: string }, context) => {
        // Must be authenticated (web user just signed in)
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "User must be authenticated"
            );
        }

        const { linkCode } = data;
        if (!linkCode || linkCode.length < 6 || linkCode.length > 8) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "Invalid link code"
            );
        }

        const uid = context.auth.uid;
        const db = admin.firestore();

        try {
            // Verify the session exists and is pending
            const sessionRef = db.collection("desktop_auth_sessions").doc(linkCode);
            const session = await sessionRef.get();

            if (!session.exists) {
                throw new functions.https.HttpsError(
                    "not-found",
                    "Session not found. Please try again from the desktop app."
                );
            }

            const sessionData = session.data()!;
            if (sessionData.status !== "pending") {
                throw new functions.https.HttpsError(
                    "already-exists",
                    "This session has already been used."
                );
            }

            // Check session age (max 10 minutes)
            const createdAt = sessionData.createdAt?.toDate();
            if (createdAt && Date.now() - createdAt.getTime() > 10 * 60 * 1000) {
                await sessionRef.delete();
                throw new functions.https.HttpsError(
                    "deadline-exceeded",
                    "Session expired. Please try again from the desktop app."
                );
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
        } catch (error) {
            if (error instanceof functions.https.HttpsError) throw error;
            console.error("Error generating desktop token:", error);
            throw new functions.https.HttpsError(
                "internal",
                "Failed to generate auth token"
            );
        }
    });

// ─── Payment Auth Token ───

/**
 * Creates a short-lived Firebase custom token for the authenticated user.
 * Used by the Flutter app to pass auth to the website pricing page so the
 * correct user account gets the subscription (not the browser's Google account).
 *
 * Flow:
 * 1. App calls createPaymentToken() (user is already signed in)
 * 2. Function returns a custom token
 * 3. App opens pricing.html?token=CUSTOM_TOKEN&plan=pro&cycle=monthly
 * 4. Pricing page calls signInWithCustomToken(token) → correct user
 */
export const createPaymentToken = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 10, memory: "256MB", maxInstances: 20 })
    .https.onCall(async (_data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "User must be authenticated"
            );
        }

        try {
            const customToken = await admin.auth().createCustomToken(context.auth.uid);
            return { success: true, token: customToken };
        } catch (error) {
            console.error("Error creating payment token:", error);
            throw new functions.https.HttpsError(
                "internal",
                "Failed to create auth token"
            );
        }
    });

// ─── Notification Cloud Functions ───

/**
 * Welcome notification when a new user completes shop setup.
 * Triggers on Firestore write when isShopSetupComplete changes to true.
 */
export const onNewUserSignup = functions
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
export const sendPushNotification = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/notifications/{notificationId}")
    .onCreate(async (snapshot, context) => {
        const userId = context.params.userId;
        const data = snapshot.data();

        if (!data) return;

        const title = data.title || "New Notification";
        const body = data.body || "";

        // Get user's FCM tokens
        const userDoc = await admin.firestore()
            .collection("users")
            .doc(userId)
            .get();

        const fcmTokens = userDoc.data()?.fcmTokens as string[] | undefined;

        if (!fcmTokens || fcmTokens.length === 0) {
            console.log(`📱 No FCM tokens for user ${userId}, skipping push`);
            return;
        }

        console.log(`📱 Sending push to ${fcmTokens.length} device(s) for user ${userId}`);

        // Send to all user's devices
        const message: admin.messaging.MulticastMessage = {
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
                const tokensToRemove: string[] = [];
                response.responses.forEach((resp, idx) => {
                    if (!resp.success && resp.error?.code === "messaging/registration-token-not-registered") {
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
        } catch (error) {
            console.error("❌ FCM send error:", error);
        }
    });

/**
 * Scheduled cleanup: delete read notifications older than 30 days.
 * Runs daily at midnight IST (18:30 UTC).
 * Uses cursor-paginated user iteration (200 users per page) to avoid full-collection scans.
 */
export const cleanupOldNotifications = functions
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
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

        do {
            let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE) as FirebaseFirestore.Query;
            if (lastDoc) query = query.startAfter(lastDoc);

            const usersPage = await query.get();
            if (usersPage.empty) break;

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
export const checkLowStock = functions
    .region("asia-south1")
    .firestore.document("users/{userId}/products/{productId}")
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();
        const userId = context.params.userId;

        const newStock = after.stock as number;
        const oldStock = before.stock as number;
        const threshold = (after.lowStockAlert as number | null) ?? 5;
        const productName = after.name || "Product";

        // Only trigger if stock dropped and is now at/below threshold
        if (newStock >= oldStock || newStock > threshold) {
            return;
        }

        // Check user preference
        const userDoc = await admin.firestore().collection("users").doc(userId).get();
        const settings = userDoc.data()?.settings || {};
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

// ─── One-Time Payment Pricing (amount in INR) ───
// Update these prices when ready for production pricing.
const PLAN_PRICES: Record<string, Record<string, number>> = {
    pro: {
        monthly: 10,   // ₹10/month
        annual: 20,    // ₹20/year
    },
    business: {
        monthly: 20,   // ₹20/month
        annual: 30,    // ₹30/year
    },
};

/**
 * Create a Razorpay Order for one-time plan payment.
 * Returns an order_id which the client uses to open Razorpay Checkout (UPI-only).
 *
 * Callable function: requires authenticated user.
 */
export const createOrder = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data: {
        plan: "pro" | "business";
        cycle: "monthly" | "annual";
    }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Login required");
        }

        const { plan, cycle } = data;
        if (!plan || !cycle || !["pro", "business"].includes(plan) || !["monthly", "annual"].includes(cycle)) {
            throw new functions.https.HttpsError("invalid-argument", "Valid plan and cycle are required");
        }

        const razorpayConfig = getRazorpayConfig();
        if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
            throw new functions.https.HttpsError("failed-precondition", "Razorpay not configured");
        }

        const amount = PLAN_PRICES[plan]?.[cycle];
        if (!amount) {
            throw new functions.https.HttpsError("not-found", `No price found for ${plan}/${cycle}`);
        }

        try {
            const authHeader = Buffer.from(`${razorpayConfig.keyId}:${razorpayConfig.keySecret}`).toString("base64");

            const response = await fetch("https://api.razorpay.com/v1/orders", {
                method: "POST",
                headers: {
                    "Authorization": `Basic ${authHeader}`,
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    amount: amount * 100, // Convert to paise
                    currency: "INR",
                    receipt: `${context.auth.uid.substring(0, 20)}_${Date.now()}`,
                    notes: {
                        userId: context.auth.uid,
                        plan,
                        cycle,
                    },
                }),
            });

            const result = await response.json();
            if (!response.ok) {
                console.error("Razorpay create order error:", result);
                throw new functions.https.HttpsError("internal",
                    result?.error?.description || "Failed to create order");
            }

            console.log(`✅ createOrder: ${result.id} for user ${context.auth.uid} (${plan}/${cycle}, ₹${amount})`);

            return {
                success: true,
                orderId: result.id,
                amount,
                plan,
                cycle,
            };
        } catch (err) {
            if (err instanceof functions.https.HttpsError) throw err;
            console.error("createOrder error:", err);
            throw new functions.https.HttpsError("internal", "Could not create order");
        }
    });

/**
 * Verify Payment — called after a successful Razorpay payment.
 * Verifies signature + payment status, then activates the plan.
 *
 * Callable function: requires authenticated user.
 */
export const verifyPayment = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 60, memory: "256MB", maxInstances: 50 })
    .https.onCall(async (data: {
        plan: "pro" | "business";
        cycle: "monthly" | "annual";
        razorpayPaymentId: string;
        razorpayOrderId: string;
        razorpaySignature: string;
    }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Login required");
        }

        const { plan, cycle, razorpayPaymentId, razorpayOrderId, razorpaySignature } = data;
        const userId = context.auth.uid;

        if (!razorpayPaymentId || !razorpayOrderId || !razorpaySignature) {
            throw new functions.https.HttpsError("invalid-argument", "razorpayPaymentId, razorpayOrderId, and razorpaySignature are required");
        }

        if (!plan || !cycle || !["pro", "business"].includes(plan) || !["monthly", "annual"].includes(cycle)) {
            throw new functions.https.HttpsError("invalid-argument", "Valid plan and cycle are required");
        }

        const razorpayConfig = getRazorpayConfig();
        if (!razorpayConfig.keyId || !razorpayConfig.keySecret) {
            throw new functions.https.HttpsError("failed-precondition", "Razorpay not configured");
        }

        // Step 1: Verify signature (order_id + "|" + payment_id signed with key_secret)
        const expectedSignature = crypto
            .createHmac("sha256", razorpayConfig.keySecret)
            .update(`${razorpayOrderId}|${razorpayPaymentId}`)
            .digest("hex");

        if (expectedSignature !== razorpaySignature) {
            console.warn(`⚠️ verifyPayment: signature mismatch for user ${userId}, order ${razorpayOrderId}`);
            throw new functions.https.HttpsError("permission-denied", "Invalid payment signature");
        }

        // Step 2: Verify payment status with Razorpay API
        const authHeader = Buffer.from(`${razorpayConfig.keyId}:${razorpayConfig.keySecret}`).toString("base64");
        try {
            const verifyRes = await fetch(
                `https://api.razorpay.com/v1/payments/${razorpayPaymentId}`,
                { headers: { Authorization: `Basic ${authHeader}` } }
            );
            if (!verifyRes.ok) {
                throw new functions.https.HttpsError("not-found", "Payment not found in Razorpay");
            }
            const payment = await verifyRes.json() as { status: string; amount: number; order_id: string };
            if (payment.status !== "captured" && payment.status !== "authorized") {
                throw new functions.https.HttpsError("failed-precondition", `Payment status is ${payment.status}, expected captured`);
            }
            // Verify the order_id matches
            if (payment.order_id !== razorpayOrderId) {
                throw new functions.https.HttpsError("permission-denied", "Order ID mismatch");
            }
            // Verify amount matches expected plan price
            const expectedAmount = (PLAN_PRICES[plan]?.[cycle] || 0) * 100;
            if (payment.amount !== expectedAmount) {
                console.warn(`⚠️ verifyPayment: amount mismatch. Expected ${expectedAmount}, got ${payment.amount}`);
                throw new functions.https.HttpsError("permission-denied", "Payment amount does not match plan price");
            }
        } catch (err: any) {
            if (err instanceof functions.https.HttpsError) throw err;
            console.error("Razorpay verification error:", err);
            throw new functions.https.HttpsError("internal", "Could not verify payment");
        }

        // Step 3: Activate the plan
        const daysToAdd = cycle === "annual" ? 365 : 30;
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + daysToAdd);

        const billsLimit = plan === "pro" ? 500 : 999999;
        const productsLimit = plan === "pro" ? 1000 : 999999;
        const customersLimit = 999999;
        const staffLimit = plan === "pro" ? 2 : 10;
        const storesLimit = plan === "pro" ? 1 : 5;

        const db = admin.firestore();

        // Update user document
        await db.collection("users").doc(userId).update({
            "subscription.plan": plan,
            "subscription.status": "active",
            "subscription.cycle": cycle,
            "subscription.startedAt": admin.firestore.FieldValue.serverTimestamp(),
            "subscription.expiresAt": admin.firestore.Timestamp.fromDate(expiresAt),
            "subscription.orderId": razorpayOrderId,
            "subscription.paymentId": razorpayPaymentId,
            "limits.billsLimit": billsLimit,
            "limits.productsLimit": productsLimit,
            "limits.customersLimit": customersLimit,
            "limits.staffLimit": staffLimit,
            "limits.storesLimit": storesLimit,
        });

        // Welcome notification
        await db.collection("users").doc(userId)
            .collection("notifications").add({
                title: `Welcome to ${plan === "pro" ? "Pro" : "Business"} Plan! 🎉`,
                body: `Your ${plan === "pro" ? "Pro" : "Business"} plan is now active. Enjoy ${plan === "pro" ? "500 bills/month" : "unlimited billing"}!`,
                type: "subscription",
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

        console.log(`✅ verifyPayment: user ${userId} activated ${plan} (${cycle}), expires ${expiresAt.toISOString()}`);

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
 * Cancel Subscription — marks subscription as cancelled.
 * The plan stays active until expiresAt, then reverts to free.
 */
export const cancelSubscription = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (_data: unknown, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Login required");
        }

        const userId = context.auth.uid;
        const db = admin.firestore();
        const userRef = db.collection("users").doc(userId);
        const userDoc = await userRef.get();

        if (!userDoc.exists) {
            throw new functions.https.HttpsError("not-found", "User not found");
        }

        const subscription = userDoc.data()?.subscription;
        if (!subscription || subscription.plan === "free") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "No active paid subscription to cancel"
            );
        }

        if (subscription.status === "cancelled") {
            throw new functions.https.HttpsError(
                "already-exists",
                "Subscription is already cancelled"
            );
        }

        await userRef.update({
            "subscription.status": "cancelled",
            "subscription.cancelledAt": admin.firestore.FieldValue.serverTimestamp(),
        });

        // Notify user
        await userRef.collection("notifications").add({
            title: "Subscription Cancelled",
            body: `Your ${subscription.plan === "pro" ? "Pro" : "Business"} plan will remain active until ${subscription.expiresAt?.toDate?.()?.toLocaleDateString?.() || "expiry"}. After that, you'll move to the Free plan.`,
            type: "subscription",
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`⚠️ cancelSubscription: user ${userId} cancelled ${subscription.plan} plan`);

        return { success: true };
    });

/**
 * Subscription Expiry Reminder — runs daily at 10 AM IST (4:30 UTC).
 * Sends reminder to users whose subscription expires within 7 days.
 * Respects user's settings.subscriptionAlerts preference.
 */
export const checkSubscriptionExpiry = functions
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
        const processUsers = async (docs: FirebaseFirestore.QueryDocumentSnapshot[]) => {
            for (const userDoc of docs) {
                const data = userDoc.data();
                if ((data.settings || {}).subscriptionAlerts === false) continue;

                const expiresAt: Date | undefined = data.subscription?.expiresAt?.toDate();
                if (!expiresAt) continue;

                const daysOffset = Math.round((expiresAt.getTime() - todayStart.getTime()) / (24 * 60 * 60 * 1000));
                if (!TOUCHPOINTS.includes(daysOffset)) continue;

                const planName = (data.subscription?.plan as string | undefined) || "Pro";
                const planLabel = planName.charAt(0).toUpperCase() + planName.slice(1);

                let title: string;
                let body: string;

                if (daysOffset === 3) {
                    title = `⚠️ ${planLabel} Plan Expires in 3 Days`;
                    body = "3 दिन बाकी — अभी renew करें और अपनी unlimited billing जारी रखें।";
                } else if (daysOffset === 1) {
                    title = `⏰ ${planLabel} Plan Expires Tomorrow!`;
                    body = `Renew now to keep your ${planLabel} features. Don't lose your 500 bills/month!`;
                } else if (daysOffset === 0) {
                    // ─── ENFORCE DOWNGRADE: Plan expired today ───
                    title = `🔴 ${planLabel} Plan Expired — Downgraded to Free`;
                    body = "Your plan has expired. You're now on the Free plan (50 bills/month). Renew anytime to get your features back.";

                    // Downgrade to free plan
                    batch.update(db.collection("users").doc(userDoc.id), {
                        "subscription.plan": "free",
                        "subscription.status": "expired",
                        "limits.billsLimit": 50,
                        "limits.productsLimit": 100,
                        "limits.customersLimit": 10,
                    });
                    batchCount++;
                } else if (daysOffset === -3) {
                    title = "You've Been on the Free Plan for 3 Days";
                    body = "Your paid plan expired 3 days ago. You're on Free (50 bills/month). Tap to upgrade.";
                } else {
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
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
        while (true) {
            let query = db
                .collection("users")
                .where("subscription.status", "==", "active")
                .where("subscription.expiresAt", "<=", sevenDaysLater)
                .orderBy("subscription.expiresAt")
                .limit(PAGE_SIZE);
            if (lastDoc) query = query.startAfter(lastDoc);

            const snap = await query.get();
            if (snap.empty) break;
            await processUsers(snap.docs);
            if (snap.size < PAGE_SIZE) break;
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
            if (lastDoc) query = query.startAfter(lastDoc);

            const snap = await query.get();
            if (snap.empty) break;
            await processUsers(snap.docs);
            if (snap.size < PAGE_SIZE) break;
            lastDoc = snap.docs[snap.docs.length - 1];
        }

        if (batchCount > 0) await batch.commit();

        console.log(`📋 Sent ${sentCount} subscription expiry reminder(s)`);
    });

// ─── Churn Detection & Re-engagement ───

/**
 * Runs daily. Detects users inactive for 7 / 14 / 30 days and sends
 * culturally-relevant re-engagement push notifications.
 * Tracks the last message sent in `activity.lastChurnMessageDays` to avoid duplicates.
 */
export const checkChurnedUsers = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 1 })
    .pubsub.schedule("0 5 * * *") // 5:00 UTC = 10:30 AM IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
        const db = admin.firestore();
        const now = new Date();
        const PAGE_SIZE = 200;

        // Touchpoint days — ordered MOST urgent first so we pick the highest applicable
        const CHURN_DAYS = [30, 14, 7] as const;

        const messages: Record<number, { title: string; body: string }> = {
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
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;

        do {
            let q = db.collection("users").orderBy("__name__").limit(PAGE_SIZE) as FirebaseFirestore.Query;
            if (lastDoc) q = q.startAfter(lastDoc);
            const page = await q.get();
            if (page.empty) break;

            for (const userDoc of page.docs) {
                const data = userDoc.data();

                // Skip users who haven't completed shop setup
                if (!data.isShopSetupComplete) continue;

                // Skip if user opted out of notifications
                if ((data.settings || {}).pushNotifications === false) continue;

                // Determine last active date
                const lastActive: Date | undefined = data.activity?.lastActiveAt?.toDate?.();
                if (!lastActive) continue;

                const daysSinceActive = Math.floor((now.getTime() - lastActive.getTime()) / (24 * 60 * 60 * 1000));

                // Find the applicable touchpoint
                const matchedDay = CHURN_DAYS.find((d) => daysSinceActive >= d);
                if (!matchedDay) continue; // active in last 7 days — skip

                // Avoid re-sending the same touchpoint
                const lastSentDays: number | undefined = data.activity?.lastChurnMessageDays;
                if (lastSentDays !== undefined && lastSentDays <= matchedDay) continue;

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
export const sendDailySalesSummary = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .pubsub.schedule("30 15 * * *") // 15:30 UTC = 9 PM IST
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
        const db = admin.firestore();
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
        const dateStr = todayStart.toISOString().split("T")[0];

        console.log("📊 Generating daily sales summaries...");

        // ── Step 1: Single collectionGroup query for all bills today ──
        const billsByUser = new Map<string, { count: number; revenue: number }>();
        let lastBillDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
        const BILL_PAGE = 5000;

        while (true) {
            let billQuery = db
                .collectionGroup("bills")
                .where("createdAt", ">=", todayStart)
                .where("createdAt", "<", todayEnd)
                .orderBy("createdAt")
                .limit(BILL_PAGE);
            if (lastBillDoc) billQuery = billQuery.startAfter(lastBillDoc);

            const billPage = await billQuery.get();
            if (billPage.empty) break;

            for (const billDoc of billPage.docs) {
                // Extract userId from path: users/{uid}/bills/{billId}
                const userId = billDoc.ref.parent.parent?.id;
                if (!userId) continue;

                const existing = billsByUser.get(userId) || { count: 0, revenue: 0 };
                existing.count++;
                existing.revenue += (billDoc.data().total as number) || 0;
                billsByUser.set(userId, existing);
            }

            if (billPage.size < BILL_PAGE) break;
            lastBillDoc = billPage.docs[billPage.docs.length - 1];
        }

        console.log(`📊 Found bills for ${billsByUser.size} user(s) today`);

        // ── Step 2: Paginate users and write notifications in batches ──
        const PAGE_SIZE = 200;
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
        let sentCount = 0;
        let batch = db.batch();
        let batchCount = 0;

        while (true) {
            let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE);
            if (lastDoc) query = query.startAfter(lastDoc);

            const usersSnapshot = await query.get();
            if (usersSnapshot.empty) break;

            for (const userDoc of usersSnapshot.docs) {
                const settings = userDoc.data().settings || {};
                if (settings.dailySummary === false) continue;

                const stats = billsByUser.get(userDoc.id);
                if (!stats || stats.count === 0) continue;

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

            if (usersSnapshot.size < PAGE_SIZE) break;
            lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
        }

        if (batchCount > 0) await batch.commit();

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
export const exchangeIdToken = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 10 })
    .https.onCall(async (data: { idToken: string }) => {
        const { idToken } = data;

        if (!idToken) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "idToken is required"
            );
        }

        try {
            // Verify the idToken to get the user's UID
            const decodedToken = await admin.auth().verifyIdToken(idToken);
            const uid = decodedToken.uid;

            console.log(`🖥️ Exchanging idToken for customToken, uid: ${uid}`);

            // Generate a custom token for this user
            const customToken = await admin.auth().createCustomToken(uid);

            return { customToken };
        } catch (error) {
            console.error("❌ exchangeIdToken error:", error);
            throw new functions.https.HttpsError(
                "internal",
                "Failed to exchange token. Please try again."
            );
        }
    });
// ─── Monthly Business Report ───

/**
 * Runs on the 1st of every month at 9 AM IST.
 * For each user, aggregates last month's bills and sends a summary notification.
 * Iterates users in pages of 200 to avoid timeout at scale.
 */
export const generateMonthlyReport = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 1 })
    .pubsub.schedule("0 3 1 * *") // 3:30 UTC = 9 AM IST on 1st of month
    .timeZone("Asia/Kolkata")
    .onRun(async () => {
        const db = admin.firestore();
        const now = new Date();

        // Compute last month's date range
        const firstOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const firstOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const monthLabel = firstOfLastMonth.toLocaleDateString("en-IN", { month: "long", year: "numeric" });
        const monthKey = `monthly_${firstOfLastMonth.getFullYear()}_${String(firstOfLastMonth.getMonth() + 1).padStart(2, "0")}`;

        console.log(`📊 Generating monthly reports for ${monthLabel}…`);

        // ── Step 1: Single collectionGroup query for all bills last month ──
        const billsByUser = new Map<string, { count: number; revenue: number }>();
        let lastBillDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
        const BILL_PAGE = 5000;

        while (true) {
            let billQuery = db
                .collectionGroup("bills")
                .where("createdAt", ">=", firstOfLastMonth)
                .where("createdAt", "<", firstOfThisMonth)
                .orderBy("createdAt")
                .limit(BILL_PAGE);
            if (lastBillDoc) billQuery = billQuery.startAfter(lastBillDoc);

            const billPage = await billQuery.get();
            if (billPage.empty) break;

            for (const billDoc of billPage.docs) {
                const userId = billDoc.ref.parent.parent?.id;
                if (!userId) continue;

                const existing = billsByUser.get(userId) || { count: 0, revenue: 0 };
                existing.count++;
                existing.revenue += (billDoc.data().total as number) ?? 0;
                billsByUser.set(userId, existing);
            }

            if (billPage.size < BILL_PAGE) break;
            lastBillDoc = billPage.docs[billPage.docs.length - 1];
        }

        console.log(`📊 Found monthly bill data for ${billsByUser.size} user(s)`);

        // ── Step 2: Paginate users, write report + notification in batches ──
        let usersProcessed = 0;
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
        const PAGE_SIZE = 200;
        let batch = db.batch();
        let batchCount = 0;

        do {
            let query = db.collection("users").orderBy("__name__").limit(PAGE_SIZE) as FirebaseFirestore.Query;
            if (lastDoc) query = query.startAfter(lastDoc);

            const page = await query.get();
            if (page.empty) break;

            for (const userDoc of page.docs) {
                const userId = userDoc.id;
                const stats = billsByUser.get(userId);
                if (!stats || stats.count === 0) continue;

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

        if (batchCount > 0) await batch.commit();

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
export const onSubscriptionWrite = functions
    .region("asia-south1")
    .firestore.document("users/{userId}")
    .onWrite(async (change, context) => {
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

        const beforePlan: string = change.before.data()?.subscription?.plan ?? "free";
        const afterPlan: string = change.after.data()?.subscription?.plan ?? "free";

        // Only act when plan changed or user was created/deleted
        const userCreated = !change.before.exists && change.after.exists;
        const userDeleted = change.before.exists && !change.after.exists;
        const planChanged = beforePlan !== afterPlan;

        if (!userCreated && !userDeleted && !planChanged) return;

        // db already declared above (L1715) — reuse it
        const statsRef = db.collection("app_config").doc("stats");

        await db.runTransaction(async (tx) => {
            // Increment/decrement counts
            const delta: Record<string, FirebaseFirestore.FieldValue> = {};

            if (userCreated) {
                delta.totalUsers = admin.firestore.FieldValue.increment(1);
                delta[`${afterPlan}Users`] = admin.firestore.FieldValue.increment(1);
            } else if (userDeleted) {
                delta.totalUsers = admin.firestore.FieldValue.increment(-1);
                delta[`${beforePlan}Users`] = admin.firestore.FieldValue.increment(-1);
            } else if (planChanged) {
                delta[`${beforePlan}Users`] = admin.firestore.FieldValue.increment(-1);
                delta[`${afterPlan}Users`] = admin.firestore.FieldValue.increment(1);
            }

            // Recompute MRR delta: subscription price only when plan is active
            const mrrMap: Record<string, number> = { free: 0, pro: 299, business: 999 };
            const mrrBefore = change.before.exists
                && change.before.data()?.subscription?.status === "active"
                ? (mrrMap[beforePlan] ?? 0) : 0;
            const mrrAfter = change.after.exists
                && change.after.data()?.subscription?.status === "active"
                ? (mrrMap[afterPlan] ?? 0) : 0;

            if (mrrAfter !== mrrBefore) {
                delta.mrr = admin.firestore.FieldValue.increment(mrrAfter - mrrBefore);
            }

            delta.updatedAt = admin.firestore.FieldValue.serverTimestamp() as unknown as FirebaseFirestore.FieldValue;

            // D1-1: Also aggregate platform and feature usage counts
            if (userCreated || userDeleted) {
                const userData = userCreated ? change.after.data() : change.before.data();
                const platform: string = (userData?.activity?.platform ?? "unknown").toLowerCase();
                const inc = userCreated ? 1 : -1;
                delta[`platformCounts.${platform}`] = admin.firestore.FieldValue.increment(inc);

                // Feature usage: check limits for billing/products/customers activity
                const limits = userData?.limits ?? {};
                if ((limits.billsThisMonth ?? 0) > 0) {
                    delta["featureUsageCounts.billing"] = admin.firestore.FieldValue.increment(inc);
                }
                if ((limits.productsCount ?? 0) > 0) {
                    delta["featureUsageCounts.products"] = admin.firestore.FieldValue.increment(inc);
                }
                if ((limits.customersCount ?? 0) > 0) {
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
export const redeemReferralCode = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 15, memory: "256MB", maxInstances: 20 })
    .https.onCall(async (data: { code: string }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Login required");
        }

        const code = String(data.code || "").toUpperCase().trim();
        if (code.length < 4 || code.length > 16) {
            throw new functions.https.HttpsError("invalid-argument", "Invalid code length");
        }

        const db = admin.firestore();
        const uid = context.auth.uid;

        const userDoc = await db.collection("users").doc(uid).get();
        if (userDoc.data()?.referredBy) {
            throw new functions.https.HttpsError("already-exists", "You have already applied a referral code");
        }

        // ── Check admin-generated promo codes first ──
        const promoDoc = await db.collection("promo_codes").doc(code).get();
        if (promoDoc.exists) {
            const promoData = promoDoc.data()!;
            if (promoData.usedBy) {
                throw new functions.https.HttpsError("already-exists", "This promo code has already been used");
            }

            const rewardDays: number = (promoData.rewardDays as number) || 30;
            const plan: string = (promoData.plan as string) || "pro";

            // Mark promo code as used (lifetime — never reusable)
            await db.collection("promo_codes").doc(code).update({
                usedBy: uid,
                usedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Apply plan + days to user
            const currentSub = userDoc.data()?.subscription || {};
            const currentExpiry: FirebaseFirestore.Timestamp | undefined = currentSub.expiresAt;
            const baseDate = currentExpiry
                ? new Date(Math.max(currentExpiry.toDate().getTime(), Date.now()))
                : new Date();
            const newExpiry = new Date(baseDate.getTime() + rewardDays * 24 * 60 * 60 * 1000);

            await db.collection("users").doc(uid).update({
                referredBy: "promo",
                referralCodeUsed: code,
                referralCodeAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
                "subscription.plan": plan,
                "subscription.status": "active",
                "subscription.expiresAt": admin.firestore.Timestamp.fromDate(newExpiry),
            });

            console.log(`🎟️ Promo code ${code} redeemed by ${uid}: ${plan} +${rewardDays}d`);
            return { success: true, type: "promo", plan, rewardDays };
        }

        // ── Fallback: check user-to-user referral codes ──
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
        return { success: true, type: "referral" };
    });

/**
 * Fires when a user's subscription changes to a paid plan. If the user was
 * referred by someone, extends the referrer's subscription by 30 days (first time only).
 */
export const processReferralReward = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 20 })
    .firestore.document("users/{userId}")
    .onUpdate(async (change, context) => {
        const beforePlan = change.before.data()?.subscription?.plan || "free";
        const afterPlan = change.after.data()?.subscription?.plan || "free";

        // Only trigger when plan upgrades from free to a paid plan
        if (beforePlan !== "free" || afterPlan === "free") return;

        const userId = context.params.userId;
        const userData = change.after.data();

        const db = admin.firestore();

        // Hardcoded referral reward settings
        const referrerDays: number = 30;
        const refereeDays: number = 30;
        const rewardBoth: boolean = true;
        const maxReferrals: number = 0; // 0 = unlimited

        const referrerId: string | undefined = userData?.referredBy;
        if (!referrerId) return;

        // Only reward once per referee
        const existing = await db.collection("referral_rewards")
            .where("refereeId", "==", userId)
            .limit(1)
            .get();
        if (!existing.empty) {
            console.log(`🔁 Referral reward already issued for referee ${userId}`);
            return;
        }

        // Check max referrals per user
        if (maxReferrals > 0) {
            const referrerRewards = await db.collection("referral_rewards")
                .where("referrerId", "==", referrerId)
                .count()
                .get();
            if ((referrerRewards.data().count || 0) >= maxReferrals) {
                console.log(`⚠️ Referrer ${referrerId} has reached max referrals (${maxReferrals})`);
                return;
            }
        }

        // Extend referrer subscription
        const referrerDoc = await db.collection("users").doc(referrerId).get();
        const currentExpiry: FirebaseFirestore.Timestamp | undefined =
            referrerDoc.data()?.subscription?.expiresAt;
        const baseDate = currentExpiry
            ? new Date(Math.max(currentExpiry.toDate().getTime(), Date.now()))
            : new Date();
        const newExpiry = new Date(baseDate.getTime() + referrerDays * 24 * 60 * 60 * 1000);

        // Extend referee subscription
        const refereeSub: FirebaseFirestore.Timestamp | undefined =
            userData?.subscription?.expiresAt;
        const refereeBase = refereeSub
            ? new Date(Math.max(refereeSub.toDate().getTime(), Date.now()))
            : new Date();
        const refereeNewExpiry = new Date(refereeBase.getTime() + (rewardBoth ? refereeDays : 0) * 24 * 60 * 60 * 1000);

        const batch = db.batch();

        // Update referrer
        batch.update(db.collection("users").doc(referrerId), {
            "subscription.expiresAt": admin.firestore.Timestamp.fromDate(newExpiry),
        });

        // Update referee (only if rewardBoth is enabled)
        if (rewardBoth) {
            batch.update(db.collection("users").doc(userId), {
                "subscription.expiresAt": admin.firestore.Timestamp.fromDate(refereeNewExpiry),
            });
        }

        // Audit trail
        const rewardRef = db.collection("referral_rewards").doc();
        batch.set(rewardRef, {
            referrerId,
            refereeId: userId,
            rewardDays: referrerDays,
            refereRewardDays: rewardBoth ? refereeDays : 0,
            bothRewarded: rewardBoth,
            rewardedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // In-app notification for referrer
        const notifRef = db.collection("users").doc(referrerId).collection("notifications").doc();
        batch.set(notifRef, {
            title: `🎁 Referral Reward! +${referrerDays} Days Free`,
            body: rewardBoth
                ? `Your friend just upgraded! You both get extra days of Pro.`
                : `Your friend just upgraded! You get +${referrerDays} extra days of Pro.`,
            type: "referral",
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // In-app notification for referee
        if (rewardBoth) {
            const refereeNotifRef = db.collection("users").doc(userId).collection("notifications").doc();
            batch.set(refereeNotifRef, {
                title: `🎁 Welcome Bonus! +${refereeDays} Days Free`,
                body: `Thanks for using a referral code! You got ${refereeDays} extra days of Pro.`,
                type: "referral",
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }

        await batch.commit();
        console.log(`🎁 Referral reward granted: referrer ${referrerId} +${referrerDays}d, referee ${userId} +${rewardBoth ? refereeDays : 0}d`);
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
export const onBillCreated = functions
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
                if (!userDoc.exists) return;

                const data = userDoc.data()!;
                const limits = data.limits || {};
                const now = new Date();
                const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;

                // Detect month rollover
                const lastResetMonth = (limits.lastResetMonth as string) || "";
                const isNewMonth = lastResetMonth !== currentMonth;
                const billsThisMonth = isNewMonth ? 0 : ((limits.billsThisMonth as number) || 0);
                const billsLimit = (limits.billsLimit as number) || 50;

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
        } catch (e) {
            console.error(`❌ onBillCreated: Failed for user ${userId}, bill ${billId}:`, e);
        }
    });

/**
 * onProductCreated — After a product is created, increment productsCount.
 * Validates limit and deletes if over (safety net).
 */
export const onProductCreated = functions
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
                if (!userDoc.exists) return;

                const data = userDoc.data()!;
                const limits = data.limits || {};
                const productsCount = (limits.productsCount as number) || 0;
                const productsLimit = (limits.productsLimit as number) || 100;

                if (productsCount >= productsLimit) {
                    console.warn(`⚠️ onProductCreated: User ${userId} OVER product limit (${productsCount}/${productsLimit}). Deleting product ${productId}.`);
                    txn.delete(snap.ref);
                    return;
                }

                txn.update(userRef, {
                    "limits.productsCount": productsCount + 1,
                });
            });
        } catch (e) {
            console.error(`❌ onProductCreated: Failed for user ${userId}, product ${productId}:`, e);
        }
    });

/**
 * onProductDeleted — Decrement productsCount when a product is deleted.
 */
export const onProductDeleted = functions
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
        } catch (e) {
            console.error(`❌ onProductDeleted: Failed for user ${userId}:`, e);
        }
    });

/**
 * onCustomerCreated — After a customer is created, increment customersCount.
 * Validates limit and deletes if over (safety net — mirrors onProductCreated).
 */
export const onCustomerCreated = functions
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
                if (!userDoc.exists) return;

                const data = userDoc.data()!;
                const limits = data.limits || {};
                const customersCount = (limits.customersCount as number) || 0;
                const customersLimit = (limits.customersLimit as number) || 10;

                if (customersCount >= customersLimit) {
                    console.warn(`⚠️ onCustomerCreated: User ${userId} OVER customer limit (${customersCount}/${customersLimit}). Deleting customer ${customerId}.`);
                    txn.delete(snap.ref);
                    return;
                }

                txn.update(userRef, {
                    "limits.customersCount": customersCount + 1,
                });
            });
        } catch (e) {
            console.error(`❌ onCustomerCreated: Failed for user ${userId}, customer ${customerId}:`, e);
        }
    });

/**
 * onCustomerDeleted — Decrement customersCount when a customer is deleted.
 */
export const onCustomerDeleted = functions
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
        } catch (e) {
            console.error(`❌ onCustomerDeleted: Failed for user ${userId}:`, e);
        }
    });

/**
 * seedAdmins — One-time callable to populate the /admins collection
 * from the hardcoded list. Run once after deploying the new rules.
 * Can be called by any existing admin (validated via old hardcoded list
 * or new collection).
 */
export const seedAdmins = functions
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
export const getSubscriptionLimits = functions
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
                customersLimit: 10,
                staffLimit: 0,
                storesLimit: 1,
                plan: "free",
                status: "active",
            };
        }

        const data = userDoc.data()!;
        const limits = data.limits || {};
        const sub = data.subscription || {};

        return {
            billsThisMonth: limits.billsThisMonth || 0,
            billsLimit: limits.billsLimit || 50,
            productsCount: limits.productsCount || 0,
            productsLimit: limits.productsLimit || 100,
            customersCount: limits.customersCount || 0,
            customersLimit: limits.customersLimit || 10,
            staffLimit: limits.staffLimit || 0,
            storesLimit: limits.storesLimit || 1,
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
export const sendNotificationToAll = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 5 })
    .https.onCall(async (data: {
        title: string;
        body: string;
        type: string;
        sentBy: string;
        data?: Record<string, unknown>;
    }, context) => {
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
        const globalRef = await db.collection("notifications").add({
            title, body, type: type || "announcement",
            targetType: "all",
            sentBy: sentBy || "system",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            ...(data.data ? { data: data.data } : {}),
        });

        let totalCount = 0;
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;

        // Paginate users 200 at a time
        while (true) {
            let query = db.collection("users").orderBy("__name__").limit(200);
            if (lastDoc) query = query.startAfter(lastDoc);
            const page = await query.get();
            if (page.empty) break;

            let batch = db.batch();
            let batchCount = 0;

            for (const userDoc of page.docs) {
                const notifRef = db
                    .collection("users").doc(userDoc.id)
                    .collection("notifications").doc();
                batch.set(notifRef, {
                    title, body, type: type || "announcement",
                    targetType: "all", sentBy: sentBy || "system",
                    read: false, readAt: null,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    globalNotificationId: globalRef.id,
                    ...(data.data ? { data: data.data } : {}),
                });
                batchCount++;
                totalCount++;

                if (batchCount >= 500) {
                    await batch.commit();
                    batch = db.batch();
                    batchCount = 0;
                }
            }

            if (batchCount > 0) await batch.commit();
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
export const sendNotificationToPlan = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 540, memory: "512MB", maxInstances: 5 })
    .https.onCall(async (data: {
        plan: string;
        title: string;
        body: string;
        type: string;
        sentBy: string;
        data?: Record<string, unknown>;
    }, context) => {
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

        const globalRef = await db.collection("notifications").add({
            title, body, type: type || "announcement",
            targetType: "plan", targetPlan: plan,
            sentBy: sentBy || "system",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            ...(data.data ? { data: data.data } : {}),
        });

        let totalCount = 0;
        let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;

        while (true) {
            let query = db.collection("users")
                .where("subscription.plan", "==", plan)
                .orderBy("__name__").limit(200);
            if (lastDoc) query = query.startAfter(lastDoc);
            const page = await query.get();
            if (page.empty) break;

            let batch = db.batch();
            let batchCount = 0;

            for (const userDoc of page.docs) {
                const notifRef = db
                    .collection("users").doc(userDoc.id)
                    .collection("notifications").doc();
                batch.set(notifRef, {
                    title, body, type: type || "announcement",
                    targetType: "plan", targetPlan: plan,
                    sentBy: sentBy || "system",
                    read: false, readAt: null,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    globalNotificationId: globalRef.id,
                    ...(data.data ? { data: data.data } : {}),
                });
                batchCount++;
                totalCount++;

                if (batchCount >= 500) {
                    await batch.commit();
                    batch = db.batch();
                    batchCount = 0;
                }
            }

            if (batchCount > 0) await batch.commit();
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
let _firestoreClient: InstanceType<typeof admin.firestore.v1.FirestoreAdminClient> | null = null;
function getFirestoreClient() {
    if (!_firestoreClient) {
        _firestoreClient = new admin.firestore.v1.FirestoreAdminClient();
    }
    return _firestoreClient;
}

export const scheduledFirestoreBackup = functions
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
            const operationName = response.name as string;
            const maxAttempts = 48; // 48 × 10s = 8 minutes
            let completed = false;

            for (let i = 0; i < maxAttempts; i++) {
                await new Promise(resolve => setTimeout(resolve, 10000)); // wait 10s

                try {
                    const operation = await firestoreClient.checkExportDocumentsProgress(operationName);
                    const op = Array.isArray(operation) ? operation[0] : operation;
                    if ((op as any).done) {
                        completed = true;
                        console.log(`✅ Firestore backup completed: ${operationName}`);
                        await admin.firestore().collection("_admin").doc("last_backup").update({
                            status: "completed",
                            completedAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        break;
                    }
                } catch (pollErr) {
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
        } catch (e) {
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
export const seedUserUsage = functions
    .region("asia-south1")
    .runWith({ timeoutSeconds: 120, memory: "512MB", maxInstances: 1 })
    .https.onCall(async (_data, context) => {
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
            const [billsCount, productsCount, expensesCount, transactionsCount] =
                await Promise.all([
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
            const hasLogo = userData.shopLogo || userData.profile?.shopLogo ? 1 : 0;
            const estimatedStorageUploadBytes = (products * 30 * 1024) + (hasLogo * 20 * 1024);
            // Downloads ~2x uploads (images displayed multiple times)
            const estimatedStorageDownloadBytes = estimatedStorageUploadBytes * 2;

            const email = userData.email || userData.profile?.email || "";
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
                periodStart: admin.firestore.Timestamp.fromDate(
                    new Date(new Date().getFullYear(), new Date().getMonth(), 1)
                ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPORT TICKET NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * onSupportMessage — When a new chat message is created in a support ticket,
 * send an FCM push notification to the other party (admin or store).
 */
export const onSupportMessage = functions
    .region("asia-south1")
    .firestore.document("support_tickets/{ticketId}/messages/{messageId}")
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        if (!data || data.type === "system") return;

        const ticketId = context.params.ticketId;
        const senderRole = data.senderRole as string;
        const senderName = data.senderName as string;
        const text = data.text as string;
        const db = admin.firestore();

        // Get the ticket to determine who to notify
        const ticketDoc = await db.collection("support_tickets").doc(ticketId).get();
        if (!ticketDoc.exists) return;

        const ticket = ticketDoc.data()!;

        if (senderRole === "store") {
            // Store sent message → notify admins
            const adminsSnap = await db.collection("admins").get();
            const adminUids: string[] = adminsSnap.docs.map(d => d.id);

            for (const adminUid of adminUids) {
                const adminDoc = await db.collection("users").doc(adminUid).get();
                const fcmTokens = adminDoc.data()?.fcmTokens as string[] | undefined;
                if (!fcmTokens || fcmTokens.length === 0) continue;

                const message: admin.messaging.MulticastMessage = {
                    tokens: fcmTokens,
                    notification: {
                        title: `💬 ${ticket.storeName}: ${ticket.subject}`,
                        body: text.length > 120 ? text.substring(0, 120) + "…" : text,
                    },
                    data: {
                        type: "support",
                        ticketId: ticketId,
                    },
                };

                try {
                    await admin.messaging().sendEachForMulticast(message);
                } catch (e) {
                    console.error(`❌ FCM to admin ${adminUid}:`, e);
                }
            }
        } else if (senderRole === "admin") {
            // Admin sent message → notify store owner
            const storeId = ticket.storeId as string;
            const userDoc = await db.collection("users").doc(storeId).get();
            const fcmTokens = userDoc.data()?.fcmTokens as string[] | undefined;

            if (!fcmTokens || fcmTokens.length === 0) {
                console.log(`📱 No FCM tokens for store ${storeId}`);
                return;
            }

            // Also create an in-app notification for the store
            const notifRef = db.collection("users").doc(storeId).collection("notifications").doc();
            await notifRef.set({
                title: "💬 Support Reply",
                body: `${senderName}: ${text.length > 80 ? text.substring(0, 80) + "…" : text}`,
                type: "support",
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const message: admin.messaging.MulticastMessage = {
                tokens: fcmTokens,
                notification: {
                    title: "💬 Support Reply",
                    body: `${senderName}: ${text.length > 120 ? text.substring(0, 120) + "…" : text}`,
                },
                data: {
                    type: "support",
                    ticketId: ticketId,
                },
            };

            try {
                const response = await admin.messaging().sendEachForMulticast(message);
                console.log(`📱 Support push to ${storeId}: ${response.successCount} sent`);
            } catch (e) {
                console.error('FCM to store error:', e);
            }
        }
    });

// --- Staff Management -------------------------------------------------------

/**
 * Create a staff member with Firebase Auth account.
 * Called by the shop owner to create a new staff user with email/password.
 */
export const createStaffUser = functions
    .region("asia-south1")
    .https.onCall(async (data: {
        email: string;
        password: string;
        name: string;
        phone: string;
        role: string;
        salary: number;
        storeId?: string;
    }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
        }

        const { email, password, name, phone, role, salary, storeId } = data;

        if (!email || !password || !name) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "email, password, and name are required"
            );
        }

        if (password.length < 6) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "Password must be at least 6 characters"
            );
        }

        const ownerId = context.auth.uid;
        const db = admin.firestore();

        // Determine the base path for staff collection
        // If storeId is provided and differs from ownerId, use stores/{storeId}
        // Otherwise use legacy users/{ownerId} path
        const basePath = (storeId && storeId !== ownerId)
            ? `stores/${storeId}`
            : `users/${ownerId}`;

        try {
            // Create Firebase Auth user for the staff member
            const userRecord = await admin.auth().createUser({
                email: email.toLowerCase().trim(),
                password: password,
                displayName: name,
                disabled: false,
            });

            // Set custom claims to link staff to owner
            await admin.auth().setCustomUserClaims(userRecord.uid, {
                staffOf: ownerId,
                role: role || "helper",
            });

            // Store staff document under the resolved base path
            await db.doc(`${basePath}/staff/${userRecord.uid}`).set({
                uid: userRecord.uid,
                name: name,
                email: email.toLowerCase().trim(),
                phone: phone || "",
                role: role || "helper",
                salary: salary || 0,
                joiningDate: admin.firestore.FieldValue.serverTimestamp(),
                isActive: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`Staff created: ${name} (${email}) for owner ${ownerId}`);

            return {
                success: true,
                uid: userRecord.uid,
                message: `Staff member ${name} created successfully`,
            };
        } catch (error: unknown) {
            const err = error as { code?: string; message?: string };
            if (err.code === "auth/email-already-exists") {
                throw new functions.https.HttpsError(
                    "already-exists",
                    "A user with this email already exists"
                );
            }
            if (err.code === "auth/invalid-email") {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "Invalid email address"
                );
            }
            console.error("Staff creation error:", error);
            throw new functions.https.HttpsError(
                "internal",
                err.message || "Failed to create staff user"
            );
        }
    });

/**
 * Deactivate a staff member's Firebase Auth account.
 */
export const deactivateStaffUser = functions
    .region("asia-south1")
    .https.onCall(async (data: { staffUid: string }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
        }

        const { staffUid } = data;
        if (!staffUid) {
            throw new functions.https.HttpsError("invalid-argument", "staffUid is required");
        }

        const ownerId = context.auth.uid;
        const db = admin.firestore();

        // Verify the staff belongs to this owner
        const staffDoc = await db
            .collection("users")
            .doc(ownerId)
            .collection("staff")
            .doc(staffUid)
            .get();

        if (!staffDoc.exists) {
            throw new functions.https.HttpsError("not-found", "Staff member not found");
        }

        try {
            await admin.auth().updateUser(staffUid, { disabled: true });
            await staffDoc.ref.update({
                isActive: false,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return { success: true, message: "Staff member deactivated" };
        } catch (error) {
            console.error("Staff deactivation error:", error);
            throw new functions.https.HttpsError("internal", "Failed to deactivate staff");
        }
    });


// --- Multi-Store User Management ------------------------------------------

/**
 * Create a new user and add them as a member to a store.
 * Creates Firebase Auth account + store membership + user store ref.
 */
export const createStoreUser = functions
    .region("asia-south1")
    .https.onCall(async (data: {
        storeId: string;
        email: string;
        displayName: string;
        password: string;
        role: string;
        permissions: Record<string, unknown>;
    }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
        }

        const { storeId, email, displayName, password, role, permissions } = data;
        if (!storeId || !email || !displayName || !password) {
            throw new functions.https.HttpsError("invalid-argument", "storeId, email, displayName, password required");
        }
        if (password.length < 6) {
            throw new functions.https.HttpsError("invalid-argument", "Password must be at least 6 characters");
        }

        const db = admin.firestore();
        const callerUid = context.auth.uid;

        // Verify caller is owner or manager of the store
        const callerMember = await db.doc(`stores/${storeId}/members/${callerUid}`).get();
        if (!callerMember.exists) {
            throw new functions.https.HttpsError("permission-denied", "You are not a member of this store");
        }
        const callerRole = callerMember.data()?.role;
        if (callerRole !== "owner" && callerRole !== "manager") {
            throw new functions.https.HttpsError("permission-denied", "Only owners and managers can add users");
        }

        try {
            // Create or get existing Firebase Auth user
            let userRecord;
            try {
                userRecord = await admin.auth().getUserByEmail(email.toLowerCase().trim());
            } catch {
                userRecord = await admin.auth().createUser({
                    email: email.toLowerCase().trim(),
                    password: password,
                    displayName: displayName,
                    disabled: false,
                });
            }

            const batch = db.batch();
            const now = admin.firestore.FieldValue.serverTimestamp();

            // Get store info for shop name
            const storeDoc = await db.doc(`stores/${storeId}`).get();
            const shopName = storeDoc.data()?.shopName || storeId;

            // Create/update user document with shop setup marked complete
            // This prevents the app from showing the "Set Up Your Shop" screen
            batch.set(db.doc(`users/${userRecord.uid}`), {
                email: email.toLowerCase().trim(),
                ownerName: displayName,
                shopName: `${shopName} (Member)`,
                isShopSetupComplete: true,
                createdAt: now,
            }, { merge: true });

            // Add as member in store
            batch.set(db.doc(`stores/${storeId}/members/${userRecord.uid}`), {
                displayName: displayName,
                email: email.toLowerCase().trim(),
                role: role || "cashier",
                permissions: permissions || {},
                joinedAt: now,
                isActive: true,
            });

            // Add store ref under user
            batch.set(db.doc(`users/${userRecord.uid}/stores/${storeId}`), {
                shopName: shopName,
                role: role || "cashier",
                isActive: true,
            });

            // Also create a staff doc so this member shows in the staff/attendance panel
            batch.set(db.doc(`stores/${storeId}/staff/${userRecord.uid}`), {
                uid: userRecord.uid,
                name: displayName,
                email: email.toLowerCase().trim(),
                phone: "",
                role: role || "cashier",
                salary: 0,
                joiningDate: now,
                isActive: true,
                createdAt: now,
            });

            await batch.commit();
            console.log(`Store user created: ${displayName} (${email}) -> store ${storeId}`);
            return { success: true, uid: userRecord.uid };
        } catch (error: unknown) {
            const err = error as { code?: string; message?: string };
            if (err.code === "auth/email-already-exists") {
                throw new functions.https.HttpsError("already-exists", "Email already exists");
            }
            console.error("createStoreUser error:", error);
            throw new functions.https.HttpsError("internal", err.message || "Failed to create user");
        }
    });

/**
 * Remove a user from a store (does NOT delete their Firebase Auth account).
 */
export const removeStoreUser = functions
    .region("asia-south1")
    .https.onCall(async (data: { storeId: string; memberUid: string }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
        }

        const { storeId, memberUid } = data;
        if (!storeId || !memberUid) {
            throw new functions.https.HttpsError("invalid-argument", "storeId and memberUid required");
        }

        const db = admin.firestore();
        const callerUid = context.auth.uid;

        // Verify caller is owner
        const callerMember = await db.doc(`stores/${storeId}/members/${callerUid}`).get();
        if (!callerMember.exists || callerMember.data()?.role !== "owner") {
            throw new functions.https.HttpsError("permission-denied", "Only the owner can remove users");
        }

        // Cannot remove yourself (owner)
        if (memberUid === callerUid) {
            throw new functions.https.HttpsError("failed-precondition", "Cannot remove yourself. Transfer ownership first.");
        }

        const batch = db.batch();
        batch.delete(db.doc(`stores/${storeId}/members/${memberUid}`));
        batch.delete(db.doc(`users/${memberUid}/stores/${storeId}`));
        await batch.commit();

        console.log(`Removed user ${memberUid} from store ${storeId}`);
        return { success: true };
    });

/**
 * Transfer store ownership to another member.
 */
export const transferStoreOwnership = functions
    .region("asia-south1")
    .https.onCall(async (data: { storeId: string; newOwnerUid: string }, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Must be authenticated");
        }

        const { storeId, newOwnerUid } = data;
        if (!storeId || !newOwnerUid) {
            throw new functions.https.HttpsError("invalid-argument", "storeId and newOwnerUid required");
        }

        const db = admin.firestore();
        const callerUid = context.auth.uid;

        // Verify caller is current owner
        const callerMember = await db.doc(`stores/${storeId}/members/${callerUid}`).get();
        if (!callerMember.exists || callerMember.data()?.role !== "owner") {
            throw new functions.https.HttpsError("permission-denied", "Only the owner can transfer ownership");
        }

        // Verify new owner is a member
        const newOwnerMember = await db.doc(`stores/${storeId}/members/${newOwnerUid}`).get();
        if (!newOwnerMember.exists) {
            throw new functions.https.HttpsError("not-found", "New owner is not a member of this store");
        }

        const newOwnerData = newOwnerMember.data()!;
        const batch = db.batch();

        // Demote current owner to manager
        batch.update(db.doc(`stores/${storeId}/members/${callerUid}`), { role: "manager" });
        batch.update(db.doc(`users/${callerUid}/stores/${storeId}`), { role: "manager" });

        // Promote new owner
        batch.update(db.doc(`stores/${storeId}/members/${newOwnerUid}`), { role: "owner" });
        batch.update(db.doc(`users/${newOwnerUid}/stores/${storeId}`), { role: "owner" });

        // Update store doc
        batch.update(db.doc(`stores/${storeId}`), {
            ownerUid: newOwnerUid,
            ownerName: newOwnerData.displayName || "",
            ownerEmail: newOwnerData.email || "",
        });

        await batch.commit();
        console.log(`Ownership transferred: store ${storeId} from ${callerUid} to ${newOwnerUid}`);
        return { success: true };
    });
