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

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.RejectedExecutionException;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Hidden case 1: exact-capacity rejection semantics of a capacity-bounded
 * event accumulator. These tests only make sense once the accumulator supports
 * an optional maximum capacity (this task's required change).
 */
public class EventAccumulatorCapacityTest {

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
    public void testRejectsEventWhenAtCapacityAndKeepsStateUnchanged() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(3);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(2, 1));
        accumulator.addLast(new MockEvent(3, 1));
        assertEquals(3, accumulator.size());

        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(4, 1)));
        assertEquals(3, accumulator.size());

        // The rejected add must not have consumed anything: the three queued
        // events are still delivered (in some key order -- the accumulator
        // picks keys at random).
        Set<Integer> delivered = new HashSet<>();
        for (int i = 0; i < 3; i++) {
            MockEvent event = accumulator.poll();
            assertEquals(1, event.value);
            delivered.add(event.key);
        }
        assertEquals(Set.of(1, 2, 3), delivered);
        assertEquals(0, accumulator.size());
        assertEquals(null, accumulator.poll());
    }

    @Test
    public void testBothAddDirectionsShareTheSameCapacity() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addFirst(new MockEvent(2, 2));
        assertEquals(2, accumulator.size());

        assertThrows(RejectedExecutionException.class, () -> accumulator.addFirst(new MockEvent(3, 3)));
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(3, 3)));
        assertEquals(2, accumulator.size());
    }

    @Test
    public void testMixedKeysAllCountAgainstTheSameCapacity() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(2);
        accumulator.addLast(new MockEvent(1, 1));
        accumulator.addLast(new MockEvent(2, 2));
        // A third distinct key is still rejected: capacity counts events, not keys.
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(3, 3)));
        assertEquals(2, accumulator.size());
    }

    @Test
    public void testRepeatedRejectionsNeverChangeSize() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(1);
        accumulator.addLast(new MockEvent(1, 1));
        for (int i = 0; i < 100; i++) {
            final int value = i;
            assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(2, value)));
            assertThrows(RejectedExecutionException.class, () -> accumulator.addFirst(new MockEvent(2, value)));
            assertEquals(1, accumulator.size());
        }
    }

    @Test
    public void testExactCapacityIsAccepted() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>(4);
        for (int i = 0; i < 4; i++) {
            accumulator.addLast(new MockEvent(i, i));
        }
        assertEquals(4, accumulator.size());
        assertThrows(RejectedExecutionException.class, () -> accumulator.addLast(new MockEvent(4, 4)));
    }

    @Test
    public void testNonPositiveCapacityIsRejectedAtConstruction() {
        assertThrows(IllegalArgumentException.class, () -> new EventAccumulator<>(0));
        assertThrows(IllegalArgumentException.class, () -> new EventAccumulator<>(-1));
        assertThrows(IllegalArgumentException.class, () -> new EventAccumulator<>(-1000));
    }

    @Test
    public void testDefaultConstructorRemainsUnbounded() {
        EventAccumulator<Integer, MockEvent> accumulator = new EventAccumulator<>();
        for (int i = 0; i < 10000; i++) {
            accumulator.addLast(new MockEvent(i % 7, i));
        }
        assertEquals(10000, accumulator.size());
    }
}