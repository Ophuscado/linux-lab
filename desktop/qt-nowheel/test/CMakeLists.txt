# The wheel test: cmake -S . -B b && cmake --build b, then with the plugin built in ../build:
#   mkdir -p p/styles && cp ../build/libbreezenowheel.so p/styles/
#   QT_QPA_PLATFORM=offscreen ./b/wheel-test Fusion                       (stock: the controls change)
#   QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH=$PWD/p LINUX_LAB_NOWHEEL_BASE=Fusion ./b/wheel-test BreezeNoWheel
# Needs Qt's private Gui headers (Fedora qt6-qtbase-private-devel) for wheel events as the window system sends them.
cmake_minimum_required(VERSION 3.16)
project(wheel_test LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Widgets Gui)
add_executable(wheel-test wheel-test.cpp)
target_link_libraries(wheel-test PRIVATE Qt6::Widgets Qt6::GuiPrivate)
