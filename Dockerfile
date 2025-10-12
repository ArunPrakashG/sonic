# syntax=docker/dockerfile:1
FROM dart:stable AS base
WORKDIR /app

# Copy pubspec first and resolve deps (better Docker caching)
COPY pubspec.yaml /app/
RUN dart pub get

# Copy the rest of the sources
COPY . /app

# Fetch deps again in case of changes
RUN dart pub get --offline || dart pub get

# Default command runs analyzer + tests
CMD ["bash", "-lc", "dart --version && dart analyze && dart test"]
