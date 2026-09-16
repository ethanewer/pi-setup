/*
 * Copyright 2015-2025 the original author or authors.
 *
 * All rights reserved. This program and the accompanying materials are
 * made available under the terms of the Eclipse Public License v2.0 which
 * accompanies this distribution and is available at
 *
 * https://www.eclipse.org/legal/epl-v20.html
 */

package org.junit.jupiter.engine.hidden.top;

import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/**
 * Top of a three-level hierarchy in which every level lives in a different
 * package and declares its own package-private test method with the same
 * signature. Java visibility rules make none of the subclass methods an
 * override of any superclass method, so all three must be discovered and
 * executed.
 *
 * @since 6.0.1
 */
public class TopLevelPackagePrivateProbeTestCase {

	static final AtomicInteger topInvocations = new AtomicInteger();

	public static void resetCounters() {
		topInvocations.set(0);
	}

	public static int topInvocationCount() {
		return topInvocations.get();
	}

	@Test
	void probe() {
		topInvocations.incrementAndGet();
	}

}