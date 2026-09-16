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

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.platform.commons.util.CollectionUtils.getOnlyElement;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.engine.AbstractJupiterTestEngineTests;
import org.junit.jupiter.engine.hidden.master.NoArgPackagePrivateMasterTestCase;

/**
 * Hidden case: the same discovery/execution code path as the upstream
 * regression test but exercised from a different signature (no parameters),
 * different class and package names, and with an additional unrelated test
 * method mixed in.
 */
class CrossPackagePackagePrivateNoArgMethodTests extends AbstractJupiterTestEngineTests {

	@Test
	void bothNoArgPackagePrivateMethodsAreDiscoveredAndExecuted() throws Exception {
		NoArgPackagePrivateMasterTestCase.resetCounters();
		DuplicateNoArgTestCase.resetCounters();

		var discoveryResults = discoverTestsForClass(DuplicateNoArgTestCase.class);
		var classDescriptor = getOnlyElement(discoveryResults.getEngineDescriptor().getChildren());

		assertThat(classDescriptor.getChildren()).hasSize(3);

		var results = executeTestsForClass(DuplicateNoArgTestCase.class);
		results.testEvents().assertStatistics(stats -> stats.started(3).succeeded(3));

		assertThat(NoArgPackagePrivateMasterTestCase.masterInvocationCount()).isEqualTo(1);
		assertThat(DuplicateNoArgTestCase.childInvocationCount()).isEqualTo(1);
		assertThat(DuplicateNoArgTestCase.extraInvocationCount()).isEqualTo(1);
	}

}