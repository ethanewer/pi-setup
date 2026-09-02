/* VLA variants: macro identifier, arithmetic expression, unsized [] */
#define MAX 40
int grid[2 * MAX][3];

int main(void)
{
    int flat[MAX];
    int partial[];
    (void)flat;
    (void)partial;
    return grid[0][0];
}
