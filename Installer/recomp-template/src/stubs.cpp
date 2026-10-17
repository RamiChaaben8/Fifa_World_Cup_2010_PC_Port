// Missing Xbox 360 kernel export stubs for 2010 FIFA World Cup South Africa (fifadllzf.xex).
// In ReXGlue, src/kernel/xboxkrnl/xboxkrnl_usbcam.cpp is not compiled into rexruntime,
// while fifadllzf.xex imports XUsbcamSetConfig (0x21C) and XUsbcamGetState (0x21D).

#include <rex/ppc.h>
#include <rex/hook.h>

// USB camera API - not present on PC, return 0 (not connected / success).
REX_EXPORT_STUB_RETURN(__imp__XUsbcamGetState, 0);
REX_EXPORT_STUB_RETURN(__imp__XUsbcamSetConfig, 0);
