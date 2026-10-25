#ifndef KEYFLOW_USB_TRANSPORT_H
#define KEYFLOW_USB_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

int keyflow_usb_write_packets(const char *library_path, const uint8_t *packets, size_t count,
                              char *error_message, size_t error_capacity);

#endif
