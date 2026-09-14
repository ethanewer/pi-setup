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
import org.junit.jupiter.engine.hidden.middle.MiddleLevelPackagePrivateProbeTestCase;
import org.junit.jupiter.engine.hidden.top.TopLevelPackagePrivateProbeTestCase;

/**
 * Hidden case: a three-level hierarchy in three different packages, every
 * level declaring its own package-private test method with the same
 * signature. None is an override, so all three must run. Exceeds the depth
 * and package count of the upstream regression test.
 */
class ThreeLevelPackagePrivateMethodTests extends AbstractJupiterTestEngineTests {

	@Test
	void allThreePackagePrivateMethodsAreDiscoveredAndExecuted() throws Exception {
		TopLevelPackagePrivateProbeTestCase.resetCounters();
		MiddleLevelPackagePrivateProbeTestCase.resetCounters();
		BottomLevelProbeTestCase.resetCounters();

		var discoveryResults = discoverTestsForClass(BottomLevelProbeTestCase.class);
		var classDescriptor = getOnlyElement(discoveryResults.getEngineDescriptor().getChildren());

		assertThat(classDescriptor.getChildren()).hasSize(3);

		var results = executeTestsForClass(BottomLevelProbeTestCase.class);
		results.testEvents().assertStatistics(stats -> stats.started(3).succeeded(3));

		assertThat(TopLevelPackagePrivateProbeTestCase.topInvocationCount()).isEqualTo(1);
		assertThat(MiddleLevelPackagePrivateProbeTestCase.middleInvocationCount()).isEqualTo(1);
		assertThat(BottomLevelProbeTestCase.bottomInvocationCount()).isEqualTo(1);
	}

}