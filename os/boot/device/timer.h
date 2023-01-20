#ifndef __TIEMR_H
#define __TIMER_H
void timer_init(void);
static void frequency_set(uint8_t counter_port, \
                          uint8_t counter_no, \
                          uint8_t rwl, \
                          uint8_t counter_mode, \
                          uint16_t counter_value \
                          );
#endif