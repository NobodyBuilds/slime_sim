#include <GLAD/glad.h>
#include <GLFW/glfw3.h>
#include "shader.h"
#include <vector>
#include "cuda.h"
#include "param.h"
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include <algorithm>
#include <cmath>
#include "ui.h"
#include <iostream>

void framebuffer_size_callback(GLFWwindow *window, int width, int height);
void processInput(GLFWwindow *window);

// settings
const unsigned int SCR_WIDTH = 1800;
const unsigned int SCR_HEIGHT = 900;
double frameTimeSec = 0.0;
int currentW = SCR_WIDTH;
int currentH = SCR_HEIGHT;
double mousex, mousey;
double prevmousex = 0, prevmousey = 0;
double dmx = 0, dmy = 0;
const float fixeddt = 1.0f / 120.0f;

int w = SCR_WIDTH / settings.tilesize;
int h = SCR_HEIGHT / settings.tilesize;








static GLuint compileShader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok)
    {
        char buf[1024];
        glGetShaderInfoLog(s, 1024, nullptr, buf);
        std::cerr << "Shader compile error: " << buf << "\n";
    }
    return s;
}
static GLuint createProgram(const char *vs, const char *fs)
{
    GLuint a = compileShader(GL_VERTEX_SHADER, vs);
    GLuint b = compileShader(GL_FRAGMENT_SHADER, fs);
    GLuint p = glCreateProgram();
    glAttachShader(p, a);
    glAttachShader(p, b);
    glLinkProgram(p);
    GLint ok;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok)
    {
        char buf[1024];
        glGetProgramInfoLog(p, 1024, nullptr, buf);
        std::cerr << "Program link error: " << buf << "\n";
    }
    glDeleteShader(a);
    glDeleteShader(b);
    return p;
}

void initshader()
{
    if (VBO)
    {
        glDeleteBuffers(1, &VBO);
        VBO = 0;
    }
    if (VAO)
    {
        glDeleteVertexArrays(1, &VAO);
        VAO = 0;
    }
    if (TEX)
    {
        glDeleteTextures(1, &TEX);
        TEX = 0;
    }

    float vertz[]{
        -1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 0.0f,
        1.0f, -1.0f, 0.0f,
        -1.0f, 1.0f, 0.0f,
        -1.0f, -1.0f, 0.0f,
        1.0f, -1.0f, 0.0f};

    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    glGenTextures(1, &TEX);

    glBindTexture(GL_TEXTURE_2D, TEX);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, w, h, 0, GL_RED, GL_FLOAT, nullptr);

    glad_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glad_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glBindVertexArray(VAO);
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertz), vertz, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), (void *)0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, TEX);
    glBindVertexArray(0);
}

void draw()
{

    glUseProgram(shaderProgram);
    glUniform2f(uresolution, (float)currentW, (float)currentH);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, TEX);
    glBindVertexArray(VAO);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);
    glUseProgram(0);
    // printf("draw\n");
}

extern "C" void restart()
{
    w = (int)currentW /settings.tilesize;
    h = (int)currentH /settings.tilesize;
    settings.w = w;
    settings.h = h;
    settings.cells = w * h;
    settings.n = settings.ncopy;
    freecuda();
    unregisterbuffer();
   
    copyparams();
    initshader();
    initcuda();
    writegenomes();
    registerBuffer(TEX);
    updateframe();

    // updateframe(w, h, data.data());
}




int main()
{
    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    GLFWwindow *window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, "hello", NULL, NULL);
    if (window == NULL)
    {
        std::cout << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSetScrollCallback(window, [](GLFWwindow *, double, double dy)
                          { settings.radius = std::clamp(settings.radius + (float)dy * 5.0f, 5.0f, 300.0f); });

    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))
    {
        std::cout << "Failed to initialize GLAD" << std::endl;
        return -1;
    }
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    (void)io;
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    const char *glsl_version = "#version 330";
    ImGui_ImplOpenGL3_Init(glsl_version);
    shaderProgram = createProgram(vertexShaderSource, fragmentShaderSource);
    glUseProgram(shaderProgram);
    {
        GLint loc = glGetUniformLocation(shaderProgram, "ushader");
        if (loc >= 0)
        {
            glUniform1i(loc, 0);
            ushader = (GLuint)loc;
        }
        loc = glGetUniformLocation(shaderProgram, "uresolution");
        if (loc >= 0)
        {
            uresolution = (GLuint)loc;
        }
    }
    glUseProgram(0);

    settings.w = w;
    settings.h = h;
    settings.cells = w * h;
    initshader();
    initcuda();
    copyparams();
    writegenomes();
    registerBuffer(TEX);
    double lastTime = glfwGetTime();
    double fpsclock = lastTime;
    float accumulator = 0.0f;
    //int frame = 0;
    // render loop
    while (!glfwWindowShouldClose(window))
    {
        extern double frameTimeSec;
        double currentTime = glfwGetTime();
        double frametime = currentTime - lastTime;
        lastTime = currentTime;
        frameTimeSec = frametime;

        accumulator += (float)frametime;
        float dt = (float)frametime;

        glfwGetCursorPos(window, &mousex, &mousey);
        dmx = mousex - prevmousex;
        dmy = mousey - prevmousey;
        prevmousex = mousex;
        prevmousey = mousey;

        processInput(window);

        while (accumulator >= fixeddt)

        {
            updatephysics();
      
            accumulator -= fixeddt;
            

           

            
        }

        // input
        // -----
    /*    frame++;
    if (settings.diverror < mindiverror) {
        mindiverror = settings.diverror;
        printf("error %3f \n sor %3f \n", mindiverror, settings.sor);

    }
    if (frame>=1000) {
        mindiverror = settings.diverror;
    }*/
        // render
        // ------
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        updateframe();
        draw();
        ui();


        glfwSwapBuffers(window);
        double elapsed = currentTime - fpsclock;
        fpsclock = currentTime;
        settings.fps = (elapsed > 0.0) ? 1.0 / elapsed : settings.fps;
        settings.fpsTimer += (float)elapsed;
        settings.fpsCount++;
        if (settings.fps > settings.maxFps)
            settings.maxFps = (float)settings.fps;
        if (settings.fps < settings.minFps)
            settings.minFps = (float)settings.fps;
        if (settings.fpsTimer >= 0.5f)
        {
            settings.avgFps = settings.fpsCount / settings.fpsTimer;
            settings.fpsTimer = 0.f;
            settings.fpsCount = 0;
        }
        settings.fuc_ms = (settings.avgFps > 0.0f) ? 1000.0f / settings.avgFps : 0.0f;

        glfwPollEvents();
    }

    if (VAO)
    {
        glDeleteVertexArrays(1, &VAO);
        VAO = 0;
    }
    if (VBO)
    {
        glDeleteBuffers(1, &VBO);
        VBO = 0;
    }
    if (TEX)
    {
        glDeleteTextures(1, &TEX);
        TEX = 0;
    }
    if (shaderProgram)
    {
        glDeleteProgram(shaderProgram);
        shaderProgram = 0;
    }

    // Cleanup CUDA resources
    unregisterbuffer();
    freecuda();

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwTerminate();
    return 0;
}

void processInput(GLFWwindow *window)

{
    if (glfwGetKey(window, GLFW_KEY_K) == GLFW_PRESS) restart();
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);

    
   
}

void framebuffer_size_callback(GLFWwindow *window, int width, int height)
{
    currentW = width;
    currentH = height;

    glViewport(0, 0, width, height);
    restart();
}