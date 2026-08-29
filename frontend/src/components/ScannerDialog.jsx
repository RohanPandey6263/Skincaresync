import { Modal } from "./ui/Modal.jsx";
import { Button } from "./ui/Button.jsx";
import { Spinner } from "./ui/Spinner.jsx";

export function ScannerDialog({ open, status, videoRef, onClose }) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Scan product code"
      description="Hold the barcode or QR code inside the frame. The ingredient list loads automatically once a code is read."
      footer={
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
      }
    >
      <div className="scanner">
        <video className="scanner__video" ref={videoRef} playsInline muted />
        <div className="scanner__reticle" aria-hidden="true" />
        {status === "requesting" ? (
          <p className="scanner__status">
            <Spinner size={15} />
            Waiting for camera permission…
          </p>
        ) : null}
      </div>
    </Modal>
  );
}
