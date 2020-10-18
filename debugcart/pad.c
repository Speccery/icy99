#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 4)
    {
        printf("usage: %s infile outfile size\n", argv[0]);
        exit(1);
    }
    
    int size = atoi(argv[3]);
    FILE *i = fopen(argv[1], "rb");
    if (!i)
    {
        printf("Unable to open file %s for read\n", argv[1]);
        exit(1);
    }
    FILE *o = fopen(argv[2], "wb");
    if (!o)
    {
        printf("Unable to open file %s for write\n", argv[2]);
        fclose(i);
        exit(1);
    }
    unsigned char byte;
    while (size > 0)
    {
        if (fread(&byte, 1, 1, i) > 0)
        {
            fwrite(&byte, 1, 1, o);
        }
        else
        {
            byte = 0;
            fwrite(&byte, 1, 1, o);
        }
        size--;
    }
    fclose(i);
    fclose(o);
    return 0;
}