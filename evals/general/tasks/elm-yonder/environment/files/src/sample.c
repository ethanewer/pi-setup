int add_twice(int x, int y);
int add_one(int v);

int main(void) {
    int a = add_twice(3, 4);
    int b = add_one(a);
    return b;
}
