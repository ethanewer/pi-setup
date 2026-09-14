/*
 * Copyright 2015-2025 the original author or authors.
 *
 * All rights reserved. This program and the accompanying materials are
 * made available under the terms of the Eclipse Public License v2.0 which
 * accompanies this distribution and is available at
 *
 * https://www.eclipse.org/legal/epl-v20.html
 */

package org.junit.jupiter.engine.hidden.middle;

import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.engine.hidden.top.TopLevelPackagePrivateProbeTestCase;

/**
 * Middle of the three-level hierarchy; in yet another package.
 *
 * @since 6.0.1
 */
public class MiddleLevelPackagePrivateProbeTestCase extends TopLevelPackagePrivateProbeTestCase {

	static final AtomicInteger middleInvocations = new AtomicInteger();

	public static void resetCounters() {
		middleInvocations.set(0);
	}

	public static int middleInvocationCount() {
		return middleInvocations.get();
	}

	@Test
	void probe() {
		middleInvocations.incrementAndGet();
	}

}