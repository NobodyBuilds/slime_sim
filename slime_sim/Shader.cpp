#include <glad/glad.h>
#include "shader.h"


GLuint VBO = 0, VAO = 0, TEX = 0;
GLuint ushader = 0;
GLuint shaderProgram = 0;
GLuint uresolution = 0;

const char* vertexShaderSource = "#version 330 core\n"
"layout (location = 0) in vec3 aPos;\n"
"out vec3 pos;\n"
"void main()\n"
"{\n"
"   gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);\n"
"   pos = aPos;\n"
"}\0";

const char* fragmentShaderSource = "#version 330 core\n"
"out vec4 FragColor;\n"
"in vec3 pos;\n"
"uniform sampler2D ushader;\n"
"uniform vec2 uresolution;"
"void main()\n"
"{\n"

"vec2 uv= gl_FragCoord.xy / uresolution;"
" float val = texture(ushader, uv).r;"




//"if(val <=0){"
"   FragColor = vec4(val+0.f,val+0.f,val+0.f, 1.0f);\n"
//"else{FragColor=vec4(val+pos.x,val+pos.y,val+pos.z, 1.0f);}"
"}\n\0";
