#ifndef SMALLPROJECT_ACCEL_DRIVER_H
#define SMALLPROJECT_ACCEL_DRIVER_H

#include <stdint.h>

#define ACCEL_BASE             0x30000000u
#define ACCEL_CTRL_OFFSET      0x00u
#define ACCEL_STATUS_OFFSET    0x04u
#define ACCEL_MODE_OFFSET      0x08u
#define ACCEL_THRESHOLD_OFFSET 0x0cu
#define ACCEL_BYPASS_OFFSET    0x10u

typedef enum {
  ACCEL_MODE_BYPASS = 0,
  ACCEL_MODE_GRAY = 1,
  ACCEL_MODE_THRESHOLD = 2
} accel_mode_t;

void accel_set_enable(uint32_t enable);
int accel_set_mode(uint32_t mode);
void accel_set_threshold(uint8_t threshold);
void accel_set_bypass(uint32_t bypass);
uint32_t accel_get_status(void);
uint32_t accel_read_enable(void);
uint32_t accel_read_mode(void);
uint32_t accel_read_threshold(void);
uint32_t accel_read_bypass(void);

#endif
