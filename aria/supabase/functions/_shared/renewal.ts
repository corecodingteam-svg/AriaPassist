// Renewal-reminder wording (pure, tested in renewal_test.ts).

export interface Notice {
  notice_id: string;
  channel: "whatsapp" | "email";
  step: "d7" | "d3" | "d1" | "d0" | "p3" | "p7" | "courtesy" | "payment_issue";
  user_id: string;
  is_owner: boolean;
  phone: string | null;
  email: string | null;
  plan_code: string;
  plan_name: string;
  circle_name: string;
  ends_at: string;
  timezone: string;
}

export function formatDate(iso: string, zone: string): string {
  return new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", timeZone: zone || "Asia/Kolkata" })
    .format(new Date(iso));
}

/** One line used by WhatsApp ({{2}}) and as the email headline. */
export function headline(n: Notice): string {
  const date = formatDate(n.ends_at, n.timezone);
  const plan = `${n.plan_name} plan`;
  switch (n.step) {
    case "d7": return `Your ${plan} ends on ${date}. Renew to keep it.`;
    case "d3": return `3 days left on your ${plan} (ends ${date}). Renew now.`;
    case "d1": return `Your ${plan} ends tomorrow. Tap to renew.`;
    case "d0": return n.is_owner
      ? `Your ${plan} has ended. Your reminders are safe — renew to get premium back.`
      : `The ${plan} for ${n.circle_name} has ended. Your reminders are safe.`;
    case "p3":
    case "p7": return `Get your ${plan} back — your reminders and shared lists are waiting.`;
    case "courtesy": return `Your ${plan} renews automatically on ${date}. Nothing to do.`;
    case "payment_issue": return `We couldn’t renew your ${plan}. Please update your payment method in the Play Store or App Store.`;
  }
}

export function whatsappMessage(n: Notice, template: string, lang = "en") {
  return {
    messaging_product: "whatsapp",
    to: (n.phone ?? "").replace(/^\+/, ""),
    type: "template",
    template: {
      name: template,
      language: { code: lang },
      components: [{
        type: "body",
        parameters: [
          { type: "text", text: n.plan_name },
          { type: "text", text: headline(n) },
        ],
      }],
    },
  };
}

export function emailMessage(n: Notice, from: string) {
  const title = headline(n);
  const cta = n.step === "courtesy" || (n.step === "d0" && !n.is_owner)
    ? ""
    : `<p><a href="aria:///subscription" style="background:#7848FF;color:#fff;padding:12px 20px;border-radius:24px;text-decoration:none">${n.step === "payment_issue" ? "Update payment" : "Renew in the app"}</a></p>`;
  return {
    from,
    to: [n.email ?? ""],
    subject: title.replace(/ — .*$/, "").slice(0, 90),
    html: `<p>${title}</p>${cta}<p style="color:#6E6487;font-size:13px">Payments are non-refundable. Basic reminders stay free forever.</p>`,
  };
}
