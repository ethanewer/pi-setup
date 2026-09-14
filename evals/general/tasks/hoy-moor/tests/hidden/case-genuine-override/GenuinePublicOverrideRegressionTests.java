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
import org.junit.jupiter.engine.hidden.master.PublicOverrideMasterTestCase;

/**
 * Hidden case on the "opposite" side of the same code path: a genuine public
 * override across packages must still be discovered exactly once (the
 * overriding method only). Guards against the fix over-generalising the rule
 * that distinguishes overrides from non-overrides.
 */
class GenuinePublicOverrideRegressionTests extends AbstractJupiterTestEngineTests {

	@Test
	void publicOverrideRunsOnlyTheOverridingMethod() throws Exception {
		PublicOverrideMasterTestCase.resetCounters();
		PublicOverrideChildTestCase.resetCounters();

		var discoveryResults = discoverTestsForClass(PublicOverrideChildTestCase.class);
		var classDescriptor = getOnlyElement(discoveryResults.getEngineDescriptor().getChildren());

		assertThat(classDescriptor.getChildren()).hasSize(1);

		var results = executeTestsForClass(PublicOverrideChildTestCase.class);
		results.testEvents().assertStatistics(stats -> stats.started(1).succeeded(1));

		assertThat(PublicOverrideMasterTestCase.masterInvocationCount()).isEqualTo(0);
		assertThat(PublicOverrideChildTestCase.childInvocationCount()).isEqualTo(1);
	}

}