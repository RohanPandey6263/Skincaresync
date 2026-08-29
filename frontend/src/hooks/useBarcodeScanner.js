import { useCallback, useEffect, useRef, useState } from "react";

const WANTED_FORMATS = ["qr_code", "ean_13", "ean_8", "upc_a", "upc_e", "code_128"];
const DETECT_INTERVAL_MS = 140;

export function useBarcodeScanner({ onDetect, onError }) {
  const [target, setTarget] = useState(null);
  const [status, setStatus] = useState("idle");
  const videoRef = useRef(null);
  const streamRef = useRef(null);
  const targetRef = useRef(null);
  const handlers = useRef({ onDetect, onError });
  // Incremented by every start/stop. A getUserMedia promise that resolves after
  // its generation has been superseded belongs to a cancelled session.
  const generationRef = useRef(0);

  handlers.current = { onDetect, onError };
  targetRef.current = target;

  const supported =
    typeof window !== "undefined" &&
    "BarcodeDetector" in window &&
    Boolean(navigator.mediaDevices?.getUserMedia);

  const releaseStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  const stop = useCallback(() => {
    generationRef.current += 1;
    releaseStream();
    setTarget(null);
    setStatus("idle");
  }, [releaseStream]);

  const start = useCallback(
    async (nextTarget) => {
      if (!supported) {
        handlers.current.onError?.(
          "This browser cannot scan with the camera. Paste the barcode or QR code instead.",
        );
        return false;
      }

      const generation = (generationRef.current += 1);
      setTarget(nextTarget);
      setStatus("requesting");
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        // The user can cancel while the browser permission prompt is open. If
        // they do, and then grant, this resolves against a session that no
        // longer exists -- without this check the camera silently switched back
        // on and the dialog reopened.
        if (generation !== generationRef.current) {
          stream.getTracks().forEach((track) => track.stop());
          return false;
        }
        streamRef.current = stream;
        setStatus("scanning");
        return true;
      } catch {
        if (generation !== generationRef.current) return false;
        setTarget(null);
        setStatus("idle");
        handlers.current.onError?.(
          "Camera access was blocked. Allow camera permission or paste the code instead.",
        );
        return false;
      }
    },
    [supported],
  );

  useEffect(() => {
    const video = videoRef.current;
    const stream = streamRef.current;
    if (status !== "scanning" || !video || !stream) return undefined;

    let frameId = 0;
    let cancelled = false;
    let lastDetectAt = 0;
    let detector = null;

    video.srcObject = stream;

    async function createDetector() {
      let formats = WANTED_FORMATS;
      try {
        const available = await window.BarcodeDetector.getSupportedFormats();
        const usable = WANTED_FORMATS.filter((format) => available.includes(format));
        if (usable.length) formats = usable;
      } catch {
        /* fall back to the full wish list */
      }
      return new window.BarcodeDetector({ formats });
    }

    async function tick(timestamp) {
      if (cancelled) return;

      if (timestamp - lastDetectAt >= DETECT_INTERVAL_MS && video.readyState >= 2) {
        lastDetectAt = timestamp;
        try {
          const codes = await detector.detect(video);
          if (cancelled) return;
          const value = codes[0]?.rawValue;
          if (value) {
            const scanTarget = targetRef.current;
            releaseStream();
            setTarget(null);
            setStatus("idle");
            handlers.current.onDetect?.(scanTarget, value);
            return;
          }
        } catch {
          // A single frame can fail to decode; keep scanning rather than
          // surfacing a transient error to the user.
        }
      }

      frameId = requestAnimationFrame(tick);
    }

    (async () => {
      try {
        detector = await createDetector();
        await video.play();
        if (cancelled) return;
        frameId = requestAnimationFrame(tick);
      } catch {
        if (cancelled) return;
        handlers.current.onError?.("The camera preview could not start. Paste the code instead.");
        stop();
      }
    })();

    return () => {
      cancelled = true;
      cancelAnimationFrame(frameId);
      video.srcObject = null;
    };
  }, [status, releaseStream, stop]);

  useEffect(() => releaseStream, [releaseStream]);

  return { supported, status, target, videoRef, start, stop, isOpen: status !== "idle" };
}
