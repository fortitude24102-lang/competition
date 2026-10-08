/* Host compilation boundary only. Production always uses the external official BSP. */
#ifndef TEST_BSP_H
#define TEST_BSP_H
#define BSP_CLINT_HZ 100000000u
void bsp_printf(const char *format,...);
#endif
