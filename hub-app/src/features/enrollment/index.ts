// First-launch enrollment flow. Renders into #app, accepts a 6-digit
// code (read aloud by the admin from /admin/devices/new), exchanges it
// for a device_token via POST /api/g2/enroll, and persists the result.

import { makeHttp } from "@transport/http";
import { setEnrollment } from "@shared/store";
import { logError } from "@services/logger";
import { ENROLLMENT_CODE_LENGTH } from "@shared/constants";

export function renderEnrollmentForm(root: HTMLElement, onDone: () => void): void {
  root.innerHTML = `
    <div class="enroll">
      <h1>Pair this Hub App</h1>
      <p class="hint">
        Ask the admin to open <code>/admin/devices/new</code> and read you
        the ${ENROLLMENT_CODE_LENGTH}-digit code.
      </p>
      <form id="enroll-form">
        <label>
          Enrollment code
          <input
            id="enroll-code"
            inputmode="numeric"
            pattern="\\d{${ENROLLMENT_CODE_LENGTH}}"
            maxlength="${ENROLLMENT_CODE_LENGTH}"
            autocomplete="one-time-code"
            required
          />
        </label>
        <label>
          Glasses serial (optional)
          <input id="enroll-serial" placeholder="G2-ABCD-1234" />
        </label>
        <button type="submit">Pair</button>
        <p id="enroll-error" class="error" hidden></p>
      </form>
    </div>
  `;

  const form = root.querySelector<HTMLFormElement>("#enroll-form")!;
  const errorEl = root.querySelector<HTMLParagraphElement>("#enroll-error")!;
  const codeInput = root.querySelector<HTMLInputElement>("#enroll-code")!;
  const serialInput = root.querySelector<HTMLInputElement>("#enroll-serial")!;

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    errorEl.hidden = true;

    const code = codeInput.value.trim();
    const glasses_serial = serialInput.value.trim() || undefined;

    try {
      const res = await makeHttp()
        .post("api/g2/enroll", {
          json: glasses_serial ? { code, glasses_serial } : { code },
        })
        .json<{ device_id: string; device_token: string; expires_in: number }>();

      setEnrollment(res.device_id, res.device_token);
      onDone();
    } catch (err) {
      logError("enroll failed", err);
      errorEl.textContent = describeEnrollError(err);
      errorEl.hidden = false;
    }
  });
}

function describeEnrollError(err: unknown): string {
  if (err && typeof err === "object" && "response" in err) {
    const resp = (err as { response?: Response }).response;
    if (resp?.status === 401)
      return "Code is invalid or expired — ask the admin to issue a new one.";
    if (resp?.status === 429)
      return "Too many attempts from this network. Wait a minute and retry.";
  }
  return "Network error — check your connection and retry.";
}
