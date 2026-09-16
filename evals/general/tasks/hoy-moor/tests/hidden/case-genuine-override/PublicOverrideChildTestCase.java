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
import org.junit.jupiter.engine.hidden.master.PublicOverrideMasterTestCase;

/**
 * Subclass in a different package that declares a PUBLIC method with the same
 * signature as the superclass's public test method. This IS a genuine
 * override (visibility makes no difference), so the superclass's method must
 * NOT be discovered: exactly one test must run.
 *
 * @since 6.0.1
 */
public class PublicOverrideChildTestCase extends PublicOverrideMasterTestCase {

	static final AtomicInteger childInvocations = new AtomicInteger();

	public static void resetCounters() {
		childInvocations.set(0);
	}

	public static int childInvocationCount() {
		return childInvocations.get();
	}

	@Override
	@Test
	public void shared() {
		childInvocations.incrementAndGet();
	}

}