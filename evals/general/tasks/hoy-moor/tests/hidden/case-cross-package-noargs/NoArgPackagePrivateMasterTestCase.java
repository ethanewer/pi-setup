/*
 * Copyright 2015-2025 the original author or authors.
 *
 * All rights reserved. This program and the accompanying materials are
 * made available under the terms of the Eclipse Public License v2.0 which
 * accompanies this distribution and is available at
 *
 * https://www.eclipse.org/legal/epl-v20.html
 */

package org.junit.jupiter.engine.hidden.master;

import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/**
 * Superclass in a different package than its subclass; declares a
 * package-private test method. Because it is package-private and the subclass
 * lives in a different package, a same-signature method in that subclass does
 * NOT override this one: both must be discovered and executed.
 *
 * @since 6.0.1
 */
public class NoArgPackagePrivateMasterTestCase {

	static final AtomicInteger masterInvocations = new AtomicInteger();

	public static void resetCounters() {
		masterInvocations.set(0);
	}

	public static int masterInvocationCount() {
		return masterInvocations.get();
	}

	@Test
	void check() {
		masterInvocations.incrementAndGet();
	}

}