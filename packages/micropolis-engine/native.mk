# Independent native build; never invokes the WASM makefile or install target.
# SPDX-License-Identifier: GPL-3.0-or-later
ENGINE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_DIR := $(abspath $(ENGINE_DIR)/../..)
BUILD_DIR ?= $(REPO_DIR)/build/native$(if $(filter 1,$(SANITIZE)),-sanitized)
CXX = c++
CC = cc
AR = ar
CPPFLAGS += -I$(ENGINE_DIR)/src -I$(ENGINE_DIR)/native/include
CXXFLAGS += -std=c++17 -O1 -g -fPIC -pthread
CFLAGS += -std=c11 -O1 -g
LDFLAGS += -pthread
ifeq ($(SANITIZE),1)
CXXFLAGS += -fsanitize=address,undefined -fno-omit-frame-pointer
CFLAGS += -fsanitize=address,undefined -fno-omit-frame-pointer
LDFLAGS += -fsanitize=address,undefined
endif
CORE_SOURCES := src/allocate.cpp \
  src/animate.cpp \
  src/budget.cpp \
  src/connect.cpp \
  src/disasters.cpp \
  src/evaluate.cpp \
  src/fileio.cpp \
  src/frontendmessage.cpp \
  src/generate.cpp \
  src/graph.cpp \
  src/initialize.cpp \
  src/map.cpp \
  src/message.cpp \
  src/micropolis.cpp \
  src/position.cpp \
  src/power.cpp \
  src/random.cpp \
  src/scan.cpp \
  src/simulate.cpp \
  src/sprite.cpp \
  src/tool.cpp \
  src/traffic.cpp \
  src/update.cpp \
  src/utilities.cpp \
  src/zone.cpp
SOURCES := $(CORE_SOURCES) native/callback.cpp native/api.cpp
OBJECTS := $(addprefix $(BUILD_DIR)/,$(SOURCES:.cpp=.o))
LIBRARY := $(BUILD_DIR)/libmicropolis_native.a
.PHONY: all test
all: $(LIBRARY)
$(BUILD_DIR)/%.o: $(ENGINE_DIR)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -c $< -o $@
$(LIBRARY): $(OBJECTS)
	$(AR) rcs $@ $^
$(BUILD_DIR)/core_test: $(ENGINE_DIR)/tests/native/core_test.cpp $(LIBRARY)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $< $(LIBRARY) $(LDFLAGS) -o $@
$(BUILD_DIR)/api_test.o: $(ENGINE_DIR)/tests/native/api_test.c $(ENGINE_DIR)/native/include/micropolis_native.h
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
$(BUILD_DIR)/api_test: $(BUILD_DIR)/api_test.o $(LIBRARY)
	$(CXX) $^ $(LDFLAGS) -o $@
$(BUILD_DIR)/gameplay_test.o: $(ENGINE_DIR)/tests/native/gameplay_test.c $(ENGINE_DIR)/native/include/micropolis_native.h
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
$(BUILD_DIR)/gameplay_test: $(BUILD_DIR)/gameplay_test.o $(LIBRARY)
	$(CXX) $^ $(LDFLAGS) -o $@
$(BUILD_DIR)/animation_test: $(ENGINE_DIR)/tests/native/animation_test.cpp $(LIBRARY)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $< $(LIBRARY) $(LDFLAGS) -o $@
test: $(BUILD_DIR)/core_test $(BUILD_DIR)/api_test $(BUILD_DIR)/gameplay_test $(BUILD_DIR)/animation_test
	$(BUILD_DIR)/core_test "$(REPO_DIR)" "$(BUILD_DIR)"
	$(BUILD_DIR)/api_test "$(REPO_DIR)" "$(BUILD_DIR)"
	$(BUILD_DIR)/gameplay_test "$(REPO_DIR)" "$(BUILD_DIR)"
	$(BUILD_DIR)/animation_test "$(REPO_DIR)" "$(BUILD_DIR)"
-include $(OBJECTS:.o=.d)
