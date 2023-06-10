#include "SFML/Graphics/Text.hpp"
#include <SFML/Graphics.hpp>

int main() {
  sf::VideoMode desktop = sf::VideoMode::getDesktopMode();
  sf::RenderWindow window(desktop, "CMake SFML Project");
  window.setFramerateLimit(144);

  // Create a graphical text to display
  sf::Font font;
  if (!font.loadFromFile("../assets/pixeled.ttf"))
    return EXIT_FAILURE;
  sf::Text text(font, "Hello, world!", 30);
  text.setPosition({100.0f, 100.0f});

  while (window.isOpen()) {
    for (auto event = sf::Event{}; window.pollEvent(event);) {
      if (event.type == sf::Event::Closed) {
        window.close();
      }
    }

    window.clear();
    window.draw(text);
    window.display();
  }
}

