/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.kafka.coordinator.common.runtime;

import java.util.concurrent.RejectedExecutionException;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden case 2: capacity reclaim semantics once events are drained from a
 * capacity-bounded event accumulator (this task's required change).
 *
 * Notes on determinism: {@code poll()} hands out random keys, so assertions
 * here are limited to sizes, rejects and values delivered at the head of a
 * single-key queue.
 */
public class EventAccumulatorReclaimTest {

    private static class MockEvent implements EventAccumulator.Event<Integer> {
        int key;
        int value;

        MockEvent(int key, int value) {
            this.key = key;
            this.value = value;
        }

        @Override
        public Integer key() {
            return key;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;

            MockEvent mockEvent = (MockEvent) o;

            if (key != mockEvent.key) return false;
            return value == mockEvent.value;
        }

        @Override
        public int hashCode() {
            int result = key;
            result = 31 * result + value;
            return result;
        }
    }

    @Test
    public void testPollFreesCapacityImmediately() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(1);
        accumulator.addLast(new MockEvent(1, 1));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(2, 2)));

        MockEvent polled = accumulator.poll();
        assertEquals(new MockEvent(1, 1), polled);
        assertEquals(0, accumulator.size());

        // The slot must be free as soon as the event is polled, before any
        // done() call.
        accumulator.addLast(new MockEvent(2, 2));
        assertEquals(1, accumulator.size());
    }

    @Test
    public void testCapacityIsFreedForAnyKeyAfterPoll() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(2, 2));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(3, 3)));

        // Poll returns one of the two queued events (random key selection), so
        // the value seen depends on which key the accumulator picked; assert
        // only that one of the two queued events came out, and that the count
        // dropped below capacity immediately (order-independent).
        MockEvent polled = accumulator.poll();
        assertTrue(polled.value == 1 || polled.value == 2,
            "polled value must be one of the queued events (1 or 2), got " + polled.value);
        assertEquals(1, accumulator.size());

        // A different key is accepted once the count drops below capacity.
        accumulator.addLast(new MockEvent(4, 4));
        assertEquals(2, accumulator.size());
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(5, 5)));
    }

    @Test
    public void testRejectedEventIsAcceptedLaterInDeliveryOrder() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(1);
        accumulator.addLast(new MockEvent(1, 1));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(2, 2)));

        assertEquals(new MockEvent(1, 1), accumulator.poll());
        accumulator.done(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(2, 2));
        assertEquals(new MockEvent(2, 2), accumulator.poll());
        assertEquals(0, accumulator.size());
    }

    @Test
    public void testDoneDoesNotByItselfFuelCapacity() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(2, 2));

        // Poll one event: one slot frees, but size() reflects queued events
        // and dropping to one must admit a new add.
        accumulator.poll();
        assertEquals(1, accumulator.size());
        accumulator.addLast(new MockEvent(3, 3));
        assertEquals(2, accumulator.size());
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(4, 4)));

        // done() releases the in-flight key but never changes size().
        accumulator.done(new MockEvent(1, 1));
        assertEquals(2, accumulator.size());
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(4, 4)));

        // Only a poll frees the slot.
        accumulator.poll();
        assertEquals(1, accumulator.size());
        accumulator.addLast(new MockEvent(4, 4));
        assertEquals(2, accumulator.size());
    }

    @Test
    public void testSameKeyCanBeRequeuedOnceDrainedBelowCapacity() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(1, 2));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(1, 3)));

        assertEquals(new MockEvent(1, 1), accumulator.poll());
        accumulator.addLast(new MockEvent(1, 3));
        assertEquals(2, accumulator.size());

        accumulator.done(new MockEvent(1, 1));
        assertEquals(new MockEvent(1, 2), accumulator.poll());
        accumulator.done(new MockEvent(1, 2));
        assertEquals(new MockEvent(1, 3), accumulator.poll());
        assertEquals(0, accumulator.size());
    }

    @Test
    public void testCapacityAccountingSurvivesAddFirstInterleaving() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addFirst(new MockEvent(2, 2));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addFirst(new MockEvent(3, 3)));

        accumulator.poll();
        assertEquals(1, accumulator.size());
        accumulator.addFirst(new MockEvent(3, 3));
        assertEquals(2, accumulator.size());
        accumulator.poll();
        accumulator.poll();
        assertEquals(0, accumulator.size());
    }
}