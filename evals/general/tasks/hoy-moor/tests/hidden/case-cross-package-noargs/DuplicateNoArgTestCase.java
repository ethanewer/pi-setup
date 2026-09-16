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
import org.junit.jupiter.engine.hidden.master.NoArgPackagePrivateMasterTestCase;

/**
 * Subclass of {@link NoArgPackagePrivateMasterTestCase} in a different
 * package. Declares a method with the same name and parameter list as the
 * inherited package-private test method; per Java visibility rules this is
 * NOT an override, so both methods must run. Also declares an unrelated
 * third test method.
 *
 * @since 6.0.1
 */
@SuppressWarnings("JUnitMalformedDeclaration")
public class DuplicateNoArgTestCase extends NoArgPackagePrivateMasterTestCase {

	static final AtomicInteger childInvocations = new AtomicInteger();
	static final AtomicInteger extraInvocations = new AtomicInteger();

	public static void resetCounters() {
		childInvocations.set(0);
		extraInvocations.set(0);
	}

	public static int childInvocationCount() {
		return childInvocations.get();
	}

	public static int extraInvocationCount() {
		return extraInvocations.get();
	}

	// @Override -- deliberately NOT an override: package-private in another package
	@Test
	void check() {
		childInvocations.incrementAndGet();
	}

	@Test
	void extra() {
		extraInvocations.incrementAndGet();
	}

}