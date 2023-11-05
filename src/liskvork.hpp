#ifndef A197BE1C_C6B9_4B18_A918_5B607480DACA
#define A197BE1C_C6B9_4B18_A918_5B607480DACA

#include "Player.hpp"
#include "configuration/ConfigHandler.hpp"

void sigchld_handler(int sig);

int liskvork(const configuration::ConfigHandler &config, lv::Player &player1, lv::Player &player2);

#endif /* A197BE1C_C6B9_4B18_A918_5B607480DACA */
