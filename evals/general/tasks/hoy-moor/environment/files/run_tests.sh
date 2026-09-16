#!/bin/bash
# Convenience wrapper: run the tree's own jupiter-tests engine slice exactly
# like the verifier does (offline; the trial has no network). Green at the
# pinned commit and must stay green after a correct fix.
set -e
cd /app/src
exec ./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.engine.LifecycleMethodOverridingTests" \
  --tests "org.junit.jupiter.engine.OverloadedTestMethodTests" \
  --tests "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests" \
  --tests "org.junit.jupiter.engine.discovery.DiscoveryTests" \
  -Ptesting.enableJaCoCo=false --offline