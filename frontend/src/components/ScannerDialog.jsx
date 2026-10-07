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
      <div className="relative aspect-[4/3] w-full overflow-hidden border-4 border-cocoa bg-cocoa">
        <video className="h-full w-full object-cover" ref={videoRef} playsInline muted />
        {/* The reticle: four red corners, the only red on the screen. */}
        <div className="pointer-events-none absolute inset-[14%]" aria-hidden="true">
          <span className="absolute left-0 top-0 h-8 w-8 border-l-4 border-t-4 border-coral" />
          <span className="absolute right-0 top-0 h-8 w-8 border-r-4 border-t-4 border-coral" />
          <span className="absolute bottom-0 left-0 h-8 w-8 border-b-4 border-l-4 border-coral" />
          <span className="absolute bottom-0 right-0 h-8 w-8 border-b-4 border-r-4 border-coral" />
        </div>
        {status === "requesting" ? (
          <p className="absolute inset-x-0 bottom-0 flex items-center gap-3 bg-cocoa px-4 py-3 font-sans text-xs label-caps text-paper">
            <Spinner size={14} />
            Waiting for camera permission…
          </p>
        ) : null}
      </div>
    </Modal>
  );
}
