// SPDX-License-Identifier: GPL-3.0-or-later
// Micropolis native frontend adapter. See ../../../MicropolisGPLLicenseNotice.md
// for the Electronic Arts copyright notice and additional GPL section 7 terms.
// No JavaScript execution. The initial C API frontend polls state, uses automatic
// budgets, and does not implement sound, robots, churches or UI dialogs.
#include "micropolis.h"
ConsoleCallback::~ConsoleCallback() {}
void ConsoleCallback::autoGoto(Micropolis *micropolis, emscripten::val callbackVal, int x, int y, std::string message) {}
void ConsoleCallback::didGenerateMap(Micropolis *micropolis, emscripten::val callbackVal, int seed) {}
void ConsoleCallback::didLoadCity(Micropolis *micropolis, emscripten::val callbackVal, std::string filename) {}
void ConsoleCallback::didLoadScenario(Micropolis *micropolis, emscripten::val callbackVals, std::string name, std::string fname) {}
void ConsoleCallback::didLoseGame(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::didSaveCity(Micropolis *micropolis, emscripten::val callbackVal, std::string filename) {}
void ConsoleCallback::didTool(Micropolis *micropolis, emscripten::val callbackVal, std::string name, int x, int y) {}
void ConsoleCallback::didWinGame(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::didntLoadCity(Micropolis *micropolis, emscripten::val callbackVal, std::string filename) {}
void ConsoleCallback::didntSaveCity(Micropolis *micropolis, emscripten::val callbackVal, std::string filename) {}
void ConsoleCallback::makeSound(Micropolis *micropolis, emscripten::val callbackVal, std::string channel, std::string sound, int x, int y) {}
void ConsoleCallback::newGame(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::saveCityAs(Micropolis *micropolis, emscripten::val callbackVal, std::string filename) {}
void ConsoleCallback::sendMessage(Micropolis *micropolis, emscripten::val callbackVal, int messageIndex, int x, int y, bool picture, bool important) {}
void ConsoleCallback::showBudgetAndWait(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::showZoneStatus(Micropolis *micropolis, emscripten::val callbackVal, int tileCategoryIndex, int populationDensityIndex, int landValueIndex, int crimeRateIndex, int pollutionIndex, int growthRateIndex, int x, int y) {}
void ConsoleCallback::simulateRobots(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::simulateChurch(Micropolis *micropolis, emscripten::val callbackVal, int posX, int posY, int churchNumber) {}
void ConsoleCallback::startEarthquake(Micropolis *micropolis, emscripten::val callbackVal, int strength) {}
void ConsoleCallback::startGame(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::startScenario(Micropolis *micropolis, emscripten::val callbackVal, int scenario) {}
void ConsoleCallback::updateBudget(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::updateCityName(Micropolis *micropolis, emscripten::val callbackVal, std::string cityName) {}
void ConsoleCallback::updateDate(Micropolis *micropolis, emscripten::val callbackVal, int cityYear, int cityMonth) {}
void ConsoleCallback::updateDemand(Micropolis *micropolis, emscripten::val callbackVal, float r, float c, float i) {}
void ConsoleCallback::updateEvaluation(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::updateFunds(Micropolis *micropolis, emscripten::val callbackVal, int totalFunds) {}
void ConsoleCallback::updateGameLevel(Micropolis *micropolis, emscripten::val callbackVal, int gameLevel) {}
void ConsoleCallback::updateHistory(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::updateMap(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::updateOptions(Micropolis *micropolis, emscripten::val callbackVal) {}
void ConsoleCallback::updatePasses(Micropolis *micropolis, emscripten::val callbackVal, int passes) {}
void ConsoleCallback::updatePaused(Micropolis *micropolis, emscripten::val callbackVal, bool simPaused) {}
void ConsoleCallback::updateSpeed(Micropolis *micropolis, emscripten::val callbackVal, int speed) {}
void ConsoleCallback::updateTaxRate(Micropolis *micropolis, emscripten::val callbackVal, int cityTax) {}
