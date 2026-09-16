/*
 * Copyright 2015-2025 the original author or authors.
 *
 * All rights reserved. This program and the accompanying materials are
 * made available under the terms of the Eclipse Public License v2.0 which
 * accompanies this distribution and is available at
 *
 * https://www.eclipse.org/legal/epl-v20.html
 */

package org.junit.jupiter.engine.hidden;

import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.engine.hidden.middle.MiddleLevelPackagePrivateProbeTestCase;

/**
 * Bottom of the three-level hierarchy; in yet another package.
 *
 * @since 6.0.1
 */
@SuppressWarnings("JUnitMalformedDeclaration")
public class BottomLevelProbeTestCase extends MiddleLevelPackagePrivateProbeTestCase {

	static final AtomicInteger bottomInvocations = new AtomicInteger();

	public static void resetCounters() {
		bottomInvocations.set(0);
	}

	public static int bottomInvocationCount() {
		return bottomInvocations.get();
	}

	@Test
	void probe() {
		bottomInvocations.incrementAndGet();
	}

}