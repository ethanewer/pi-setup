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
 * Superclass in a different package than its subclass; declares a PUBLIC test
 * method. Here the subclass's same-signature method IS a genuine override,
 * so only the subclass's method must be discovered and executed.
 *
 * @since 6.0.1
 */
public class PublicOverrideMasterTestCase {

	static final AtomicInteger masterInvocations = new AtomicInteger();

	public static void resetCounters() {
		masterInvocations.set(0);
	}

	public static int masterInvocationCount() {
		return masterInvocations.get();
	}

	@Test
	public void shared() {
		masterInvocations.incrementAndGet();
	}

}