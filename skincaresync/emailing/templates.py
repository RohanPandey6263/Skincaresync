"""Authentication email templates.

Colours and type are lifted from `frontend/src/styles/tokens.css` so mail looks
like the product. They are inlined literals rather than variables because email
clients do not support custom properties, and are marked with the token name
they mirror so the two can be kept in step.

Every message is sent as text and HTML. Links are absolute URLs built from the
validated APP_BASE_URL, never from a request header.
"""

from __future__ import annotations

from html import escape

from .sender import OutboundEmail

# Mirrors tokens.css: --forest / --cream / --ink / --text-muted / --line.
_FOREST = "#1e3227"
_CREAM = "#f5f1e8"
_INK = "#12211a"
_MUTED = "#5c6b62"
_LINE = "#dcd6c8"
_FONT = (
    "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
)


def _layout(heading: str, body_html: str, cta_label: str, cta_url: str, footer: str) -> str:
    return f"""\
<!doctype html>
<html lang="en">
<body style="margin:0;padding:0;background:{_CREAM};font-family:{_FONT};color:{_INK};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="background:{_CREAM};padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:520px;background:#ffffff;border:1px solid {_LINE};
                    border-radius:14px;overflow:hidden;">
        <tr><td style="background:{_FOREST};padding:20px 28px;">
          <span style="color:{_CREAM};font-size:17px;font-weight:600;
                       letter-spacing:-0.01em;">SkincareSync</span>
        </td></tr>
        <tr><td style="padding:28px;">
          <h1 style="margin:0 0 14px;font-size:20px;line-height:1.3;color:{_INK};">
            {escape(heading)}</h1>
          {body_html}
          <table role="presentation" cellpadding="0" cellspacing="0" style="margin:26px 0 10px;">
            <tr><td style="border-radius:9px;background:{_FOREST};">
              <a href="{escape(cta_url, quote=True)}"
                 style="display:inline-block;padding:12px 22px;color:{_CREAM};
                        text-decoration:none;font-weight:600;font-size:15px;">
                {escape(cta_label)}</a>
            </td></tr>
          </table>
          <p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:{_MUTED};">
            If the button does not work, copy this link into your browser:<br>
            <span style="word-break:break-all;color:{_MUTED};">
              {escape(cta_url)}</span>
          </p>
        </td></tr>
        <tr><td style="padding:16px 28px 24px;border-top:1px solid {_LINE};">
          <p style="margin:0;font-size:12px;line-height:1.6;color:{_MUTED};">{footer}</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"""


def _paragraph(text: str) -> str:
    return (
        f'<p style="margin:0 0 12px;font-size:15px;line-height:1.6;color:{_INK};">'
        f"{escape(text)}</p>"
    )


def verification_email(to: str, verify_url: str, expires_hours: int) -> OutboundEmail:
    text = (
        "Confirm your email address\n\n"
        "Open this link to finish setting up your SkincareSync account:\n\n"
        f"{verify_url}\n\n"
        f"The link works once and expires in {expires_hours} hours.\n\n"
        "If you did not create an account, you can ignore this message."
    )
    html = _layout(
        heading="Confirm your email address",
        body_html=_paragraph(
            "Confirm this address to finish setting up your SkincareSync account."
        ),
        cta_label="Confirm email address",
        cta_url=verify_url,
        footer=(
            f"This link can be used once and expires in {expires_hours} hours. "
            "If you did not create an account, you can safely ignore this email."
        ),
    )
    return OutboundEmail(to=to, subject="Confirm your SkincareSync email", text_body=text, html_body=html)


def password_reset_email(to: str, reset_url: str, expires_minutes: int) -> OutboundEmail:
    text = (
        "Reset your password\n\n"
        "Open this link to choose a new SkincareSync password:\n\n"
        f"{reset_url}\n\n"
        f"The link works once and expires in {expires_minutes} minutes.\n\n"
        "If you did not request this, no action is needed and your password is unchanged."
    )
    html = _layout(
        heading="Reset your password",
        body_html=_paragraph("Choose a new password for your SkincareSync account."),
        cta_label="Choose a new password",
        cta_url=reset_url,
        footer=(
            f"This link can be used once and expires in {expires_minutes} minutes. "
            "If you did not request a reset, no action is needed and your password "
            "has not changed."
        ),
    )
    return OutboundEmail(to=to, subject="Reset your SkincareSync password", text_body=text, html_body=html)


def password_changed_email(to: str, manage_url: str) -> OutboundEmail:
    """Sent after a password change or reset. This is the tripwire that tells a
    user their account was taken over, so it is sent even though nothing is
    required of them."""
    text = (
        "Your password was changed\n\n"
        "The password on your SkincareSync account was just changed, and all "
        "other signed-in devices were signed out.\n\n"
        "If this was not you, reset your password immediately:\n\n"
        f"{manage_url}"
    )
    html = _layout(
        heading="Your password was changed",
        body_html=_paragraph(
            "The password on your SkincareSync account was just changed, and every "
            "other signed-in device was signed out."
        ),
        cta_label="Review account security",
        cta_url=manage_url,
        footer="If this was not you, reset your password immediately using the link above.",
    )
    return OutboundEmail(to=to, subject="Your SkincareSync password was changed", text_body=text, html_body=html)
