import fetch from "node-fetch";
import { APPROVE_FUNCTION_URL } from "./config";
import { StoryProposal } from "./schemas";

export interface ProposalEmailItem {
  proposalId: string;
  proposal: StoryProposal;
  sketchUrl: string | null;
  approveUrl: string;
  rejectUrl: string;
}

export function buildApprovalUrl(
  proposalId: string,
  action: "approve" | "reject",
  expiresAtMs: number,
  token: string
): string {
  const params = new URLSearchParams({
    id: proposalId,
    action,
    exp: String(expiresAtMs),
    token,
  });
  return `${APPROVE_FUNCTION_URL}?${params.toString()}`;
}

function langLabel(lang: string): string {
  return lang === "te" ? "\u{1F1EE}\u{1F1F3} Telugu" : "\u{1F1EC}\u{1F1E7} English";
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildProposalEmailHtml(items: ProposalEmailItem[], dateLabel: string): string {
  const cards = items
    .map((item) => {
      const p = item.proposal;
      const sketch = item.sketchUrl
        ? `<img src="${item.sketchUrl}" alt="Character sketch of ${escapeHtml(p.heroName)}"
             style="width:200px;height:200px;object-fit:contain;border-radius:12px;background:#fff;border:1px solid #eee;" />`
        : `<div style="width:200px;height:200px;border-radius:12px;background:#f5f0e6;display:flex;align-items:center;justify-content:center;color:#999;">sketch unavailable</div>`;

      return `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="background:#ffffff;border-radius:16px;border:1px solid #eee;margin-bottom:24px;">
        <tr>
          <td style="padding:24px;">
            <div style="font-size:13px;color:#b07030;font-weight:bold;margin-bottom:4px;">
              ${langLabel(p.language)} &nbsp;&bull;&nbsp; Ages ${escapeHtml(p.ageBand)}
            </div>
            <h2 style="margin:0 0 12px 0;font-size:22px;color:#333;">${escapeHtml(p.title)}</h2>
            <table role="presentation" cellpadding="0" cellspacing="0"><tr>
              <td valign="top" style="padding-right:20px;">${sketch}</td>
              <td valign="top">
                <p style="margin:0 0 10px 0;color:#444;line-height:1.5;">${escapeHtml(p.premise)}</p>
                <p style="margin:0 0 6px 0;color:#666;font-size:14px;">
                  <b>Hero:</b> ${escapeHtml(p.heroName)} &mdash; ${escapeHtml(p.heroDescription)}</p>
                <p style="margin:0 0 6px 0;color:#666;font-size:14px;"><b>Setting:</b> ${escapeHtml(p.setting)}</p>
                <p style="margin:0;color:#666;font-size:14px;"><b>Lesson:</b> ${escapeHtml(p.moral)}</p>
              </td>
            </tr></table>
            <div style="margin-top:18px;">
              <a href="${item.approveUrl}"
                 style="display:inline-block;background:#4caf50;color:#fff;text-decoration:none;
                        padding:12px 28px;border-radius:999px;font-weight:bold;margin-right:12px;">
                &#10003; Approve</a>
              <a href="${item.rejectUrl}"
                 style="display:inline-block;background:#f5f5f5;color:#888;text-decoration:none;
                        padding:12px 28px;border-radius:999px;font-weight:bold;">&#10005; Skip</a>
            </div>
          </td>
        </tr>
      </table>`;
    })
    .join("\n");

  return `<!DOCTYPE html>
<html><body style="margin:0;padding:0;background:#faf6ee;font-family:Georgia,'Times New Roman',serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px;">
    <table role="presentation" width="640" cellpadding="0" cellspacing="0" style="max-width:640px;width:100%;">
      <tr><td style="padding-bottom:24px;text-align:center;">
        <h1 style="margin:0;color:#b07030;font-size:26px;">&#128218; Suzy Story Studio</h1>
        <p style="margin:8px 0 0 0;color:#888;">Today's story proposals &mdash; ${escapeHtml(dateLabel)}</p>
      </td></tr>
      <tr><td>${cards}</td></tr>
      <tr><td style="text-align:center;color:#aaa;font-size:12px;padding-top:8px;">
        Approved stories are written, illustrated, and published to the app automatically.<br/>
        Links expire in 7 days.
      </td></tr>
    </table>
  </td></tr></table>
</body></html>`;
}

export async function sendEmail(
  sendgridKey: string,
  to: string,
  from: string,
  subject: string,
  html: string
): Promise<void> {
  const resp = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${sendgridKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: from, name: "Suzy Story Studio" },
      subject,
      content: [{ type: "text/html", value: html }],
    }),
  });
  if (!resp.ok) {
    throw new Error(`SendGrid error ${resp.status}: ${(await resp.text()).slice(0, 500)}`);
  }
}
