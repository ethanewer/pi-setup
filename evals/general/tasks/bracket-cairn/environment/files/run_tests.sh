#!/bin/bash
# Convenience wrapper: run the platform-tests reflection slice exactly like the
# verifier does (offline; the trial has no network). Green at the pinned commit.
set -e
cd /app/src
exec ./gradlew :platform-tests:test \
  --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
  --tests "org.junit.platform.commons.support.ReflectionSupportTests" \
  -Ptesting.enableJaCoCo=false --offline