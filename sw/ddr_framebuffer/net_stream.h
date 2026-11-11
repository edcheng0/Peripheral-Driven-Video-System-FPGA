/* net_stream.h - Ethernet video streaming (only built into the Ethernet version of the ARM program) */
#ifndef NET_STREAM_H
#define NET_STREAM_H

void net_poll(void);      /* call as often as possible from the main loop */
void net_status(void);    /* print one line with the network state */

#endif
