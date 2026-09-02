/*
 * probe.cpp - a declaratively empty consumer for cardinal.h.
 *
 * This translation unit includes the Cardinal public header and builds nothing
 * functional besides a trivial consumer. It is used to prove the header is
 * strict-C++11-clean: it must compile with g++ under  -std=c++11.
 * The produced object is the deliverable /app/probe.o.
 */
#include "cardinal.h"

static cardinal_seal make_seal(void)
{
    cardinal_seal s;
    s.block_id = 0UL;
    s.span = CARDINAL_LITERAL_MAX;
    return s;
}

volatile unsigned long probe_fence;

int main(void)
{
    cardinal_seal v = make_seal();
    probe_fence = v.block_id + v.span;
    return 0;
}