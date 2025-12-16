## Camera Intrinsics Calibration

- The Camera Intrinsics screen streams live video and reads the per-frame intrinsic matrix provided by the system via `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`.
- You can choose the calibration resolution from the segmented control: default `1920×1440` or `640×480`. The app reconfigures the capture session to that preset and shows the actual frame dimensions it is calibrating against.
- No chessboard or still capture is required—the intrinsics come directly from Core Media for the active camera preset. Use an external calibration workflow only if you need distortion coefficients or to validate/override the system values.
