#include "USBTransport.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef struct libusb_context libusb_context;
typedef struct libusb_device_handle libusb_device_handle;
typedef int (*libusb_init_fn)(libusb_context **);
typedef libusb_device_handle *(*libusb_open_device_fn)(libusb_context *, uint16_t, uint16_t);
typedef int (*libusb_claim_interface_fn)(libusb_device_handle *, int);
typedef int (*libusb_interrupt_transfer_fn)(libusb_device_handle *, unsigned char,
                                             unsigned char *, int, int *, unsigned int);
typedef int (*libusb_release_interface_fn)(libusb_device_handle *, int);
typedef void (*libusb_close_fn)(libusb_device_handle *);
typedef void (*libusb_exit_fn)(libusb_context *);
typedef const char *(*libusb_error_name_fn)(int);

static void set_error(char *buffer, size_t capacity, const char *message) {
    if (buffer && capacity) snprintf(buffer, capacity, "%s", message);
}

int keyflow_usb_write_packets(const char *library_path, const uint8_t *packets, size_t count,
                              char *error_message, size_t error_capacity) {
    if (!library_path || !packets || count == 0) return 0;
    if (error_message && error_capacity) error_message[0] = '\0';

    void *library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        set_error(error_message, error_capacity, dlerror());
        return -1;
    }

    libusb_init_fn init_usb = (libusb_init_fn)dlsym(library, "libusb_init");
    libusb_open_device_fn open_device = (libusb_open_device_fn)dlsym(library, "libusb_open_device_with_vid_pid");
    libusb_claim_interface_fn claim_interface = (libusb_claim_interface_fn)dlsym(library, "libusb_claim_interface");
    libusb_interrupt_transfer_fn interrupt_transfer = (libusb_interrupt_transfer_fn)dlsym(library, "libusb_interrupt_transfer");
    libusb_release_interface_fn release_interface = (libusb_release_interface_fn)dlsym(library, "libusb_release_interface");
    libusb_close_fn close_device = (libusb_close_fn)dlsym(library, "libusb_close");
    libusb_exit_fn exit_usb = (libusb_exit_fn)dlsym(library, "libusb_exit");
    libusb_error_name_fn error_name = (libusb_error_name_fn)dlsym(library, "libusb_error_name");
    if (!init_usb || !open_device || !claim_interface || !interrupt_transfer ||
        !release_interface || !close_device || !exit_usb || !error_name) {
        set_error(error_message, error_capacity, "Bundled libusb is missing required functions");
        dlclose(library);
        return -1;
    }

    libusb_context *context = NULL;
    libusb_device_handle *device = NULL;
    int claimed = 0;
    int outcome = -1;
    int error = init_usb(&context);
    if (error != 0) {
        snprintf(error_message, error_capacity, "libusb initialization failed: %s", error_name(error));
        goto cleanup;
    }

    device = open_device(context, 0x1189, 0x8890);
    if (!device) {
        set_error(error_message, error_capacity, "Macropad 1189:8890 is not available to libusb");
        outcome = -2;
        goto cleanup;
    }

    error = claim_interface(device, 1);
    if (error != 0) {
        snprintf(error_message, error_capacity, "Could not claim macropad interface 1: %s", error_name(error));
        goto cleanup;
    }
    claimed = 1;

    for (size_t index = 0; index < count; index++) {
        int transferred = 0;
        error = interrupt_transfer(device, 0x02, (unsigned char *)(packets + index * 64),
                                  64, &transferred, 1000);
        if (error != 0 || transferred != 64) {
            snprintf(error_message, error_capacity,
                     "USB write failed at packet %zu of %zu (%s; wrote %d of 64 bytes)",
                     index + 1, count, error_name(error), transferred);
            goto cleanup;
        }
    }
    outcome = 0;

cleanup:
    if (claimed) release_interface(device, 1);
    if (device) close_device(device);
    if (context) exit_usb(context);
    dlclose(library);
    return outcome;
}
