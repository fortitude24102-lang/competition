#ifndef SMALLPROJECT_UART_H
#define SMALLPROJECT_UART_H

#include <stdint.h>

void uart_putc(uint8_t byte);
void uart_puts(const char *text);
uint8_t uart_getc(void);
int uart_readline(char *buffer, uint32_t capacity);

#endif
