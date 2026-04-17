#include <iostream>
#include "lib/lib.h"

int main() {
  // Use library through transitioned dependency
  int result1 = add(5, 3);
  std::cout << "Transitioned: 5 + 3 = " << result1 << std::endl;
  
  // Use library through normal dependency
  int result2 = add(10, 7);
  std::cout << "Normal: 10 + 7 = " << result2 << std::endl;
  
  return 0;
}
