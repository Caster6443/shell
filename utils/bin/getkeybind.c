#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_LINE 1024
#define MAX_LEN 512
#define INFO_LEN 1024
#define GROUP_NUM 4

struct keybind_info {
  char command[MAX_LEN];     // store key
  char description[MAX_LEN]; // store value
};

struct Category {
  char name[GROUP_NUM];
  struct keybind_info list[INFO_LEN];
  int count;
};

struct Category group[GROUP_NUM] = {
    {"app", {}, 0}, {"win", {}, 0}, {"sys", {}, 0}, {"msc", {}, 0}};

struct HyprVars {
  char name[MAX_LEN];  // store "$xxx"
  char value[MAX_LEN]; // store value
};
struct HyprVars var_list[INFO_LEN];

void get_sym(struct HyprVars *dest, char *sym_ptr, int count);
void get_def(struct HyprVars *dest, char *def_ptr, int count);
int cmp_var(const void *a, const void *b);
void get_value(struct keybind_info *dest, char *value_ptr, int count);
void replace_ch(char *key_ptr);
void get_key(struct keybind_info *dest, char *key_ptr, int count);
void translate_all_keybinds(struct keybind_info *list, int list_size,
                            struct HyprVars *var_list, int var_total);
void wash_data(struct keybind_info *target_list, int count);
void print_json(struct Category *group_array, int group_total);

int main(int argc, char *argv[]) {
  int count = 0;
  char *target_path;
  char *target_file;
  char line[MAX_LINE];
  if (argc >= 3) {
    target_path = argv[1];
    target_file = argv[2];
  } else {
    fprintf(
        stderr,
        "Usage: %s <config_file_path> <variable_file_path>\nSuch as: %s "
        "~/.config/hypr/hyprland/keybinds.conf ~/.config/hypr/variables.conf\n",
        argv[0], argv[0]);
    exit(EXIT_FAILURE);
  }

  FILE *fb = fopen(target_file, "r");
  if (!fb) {
    fprintf(stderr, "error: Can't open file %s\n", target_file);
    exit(EXIT_FAILURE);
  }
  while (fgets(line, sizeof(line), fb)) {
    line[strcspn(line, "\n")] = '\0';
    char *sym_ptr = strchr(line, '$'); // key
    if (!sym_ptr)
      continue;
    get_sym(var_list, sym_ptr, count);
    char *def_ptr = strchr(line, '='); // value
    get_def(var_list, ++def_ptr, count);

    count++;
    if (count >= INFO_LEN - 1)
      break;
  }
  qsort(var_list, count, sizeof(struct HyprVars),
        cmp_var); // sort varlist a-Z
  fclose(fb);
  int var_total = count;

  count = 0;

  FILE *fp = fopen(target_path, "r");
  if (!fp) {
    fprintf(stderr, "error: Can't open file %s\n", target_path);
    exit(EXIT_FAILURE);
  }
  while (fgets(line, sizeof(line), fp)) {
    line[strcspn(line, "\n")] = '\0';

    char *marker_ptr = strstr(line, "#@");
    if (marker_ptr == NULL)
      continue;

    char *temp_check = strstr(line, "bind");
    temp_check--;
    if (*temp_check == '#')
      continue;

    int idx = -1;

    if (strncmp(marker_ptr, "#@app", 5) == 0)
      idx = 0;
    else if (strncmp(marker_ptr, "#@win", 5) == 0)
      idx = 1;
    else if (strncmp(marker_ptr, "#@sys", 5) == 0)
      idx = 2;
    else if (strncmp(marker_ptr, "#@msc", 5) == 0)
      idx = 3;

    if (idx == -1)
      continue;

    struct Category *target = &group[idx];

    get_value(target->list, marker_ptr + 5, target->count);

    char *key_ptr = strstr(line, "#@");
    *key_ptr = '\0';
    key_ptr = strstr(line, "=");
    key_ptr++;

    get_key(target->list, key_ptr, target->count);
    target->count++;

    count++;
    if (count >= INFO_LEN - 1)
      break;
  }

  for (int i = 0; i < GROUP_NUM; i++) {
    translate_all_keybinds(group[i].list, group[i].count, var_list, var_total);
    wash_data(group[i].list, group[i].count);
  }

  print_json(group, GROUP_NUM);

  fclose(fp);

  return 0;
}

void get_sym(struct HyprVars *dest, char *sym_ptr, int count) {
  int i = 0;
  char *temp_ptr = sym_ptr;
  while (*temp_ptr != '\0' && !isspace((unsigned char)*temp_ptr) &&
         *temp_ptr != '=' && i < MAX_LEN - 1) {
    dest[count].name[i] = *temp_ptr;
    i++;
    temp_ptr++;
  }
  dest[count].name[i] = '\0';
}

void get_def(struct HyprVars *dest, char *def_ptr, int count) {
  while (isspace(*def_ptr))
    def_ptr++;

  strncpy(dest[count].value, def_ptr, MAX_LEN - 1);
  dest[count].value[MAX_LEN - 1] = '\0';
  replace_ch(dest[count].value);
  char *end = dest[count].value + strlen(dest[count].value) - 1;
  while (end >= dest[count].value && isspace((unsigned char)*end)) {
    *end = '\0';
    end--;
  }
}

int cmp_var(const void *a, const void *b) {
  struct HyprVars *var_a = (struct HyprVars *)a;
  struct HyprVars *var_b = (struct HyprVars *)b;
  return strcmp(var_a->name, var_b->name);
}

void get_value(struct keybind_info *dest, char *value_ptr, int count) {
  while (isspace(*value_ptr)) {
    value_ptr++;
  }
  strncpy(dest[count].description, value_ptr, MAX_LEN - 1);
  dest[count].description[MAX_LEN - 1] = '\0';
}

void replace_ch(char *key_ptr) {
  char *src = key_ptr;
  char *dst = key_ptr;
  int in_space = 0;

  while (*src != '\0') {
    if (*src == ',' || *src == '+' || isspace((unsigned char)*src)) {
      if (!in_space) {
        *dst++ = ' ';
        in_space = 1;
      }
    } else {
      *dst++ = *src;
      in_space = 0;
    }
    src++;
  }

  *dst = '\0';
}

void get_key(struct keybind_info *dest, char *key_ptr, int count) {
  while (isspace(*key_ptr))
    key_ptr++;

  int target_commas = 2;

  if (*key_ptr == '$') {
    char temp_str[MAX_LEN];
    strncpy(temp_str, key_ptr, MAX_LEN - 1);
    temp_str[MAX_LEN - 1] = '\0';

    char *first_comma = strchr(temp_str, ',');
    if (first_comma) {
      char *t2 = first_comma + 1;
      while (isspace(*t2))
        t2++;

      char *end = t2;
      while (*end != '\0' && *end != ',' && !isspace((unsigned char)*end))
        end++;
      *end = '\0';

      if (strlen(t2) > 1 && strcmp(t2, "up") != 0 && strcmp(t2, "down") != 0 &&
          strcmp(t2, "left") != 0 && strcmp(t2, "right") != 0) {
        target_commas = 1;
      }
    }
  }

  int mas = 0;
  char *p = key_ptr;
  while (*p != '\0') {
    if (*p == ',') {
      if (++mas == target_commas) {
        *p = '\0';
        break;
      }
    }
    p++;
  }

  if (*key_ptr == ',')
    key_ptr++;
  while (isspace((unsigned char)*key_ptr))
    key_ptr++;

  char *end = key_ptr + strlen(key_ptr) - 1;
  while (end >= key_ptr && isspace((unsigned char)*end)) {
    *end = '\0';
    end--;
  }
  replace_ch(key_ptr);

  strncpy(dest[count].command, key_ptr, MAX_LEN - 1);
  dest[count].command[MAX_LEN - 1] = '\0';
}

void translate_all_keybinds(struct keybind_info *list, int list_size,
                            struct HyprVars *var_list, int var_total) {

  for (int i = 0; i < list_size; i++) {
    char final_res[MAX_LEN] = {0};
    char temp_src[MAX_LEN] = {0};

    strncpy(temp_src, list[i].command, MAX_LEN - 1);

    char *token = strtok(temp_src, " ");
    while (token) {
      if (token[0] == '$') {
        struct HyprVars key;
        strncpy(key.name, token, MAX_LEN - 1);
        key.name[MAX_LEN - 1] = '\0';

        struct HyprVars *res = bsearch(&key, var_list, var_total,
                                       sizeof(struct HyprVars), cmp_var);

        if (res) {
          strncat(final_res, res->value, MAX_LEN - strlen(final_res) - 1);
        } else {
          strncat(final_res, token, MAX_LEN - strlen(final_res) - 1);
        }
      } else {
        strncat(final_res, token, MAX_LEN - strlen(final_res) - 1);
      }

      strncat(final_res, " ", MAX_LEN - strlen(final_res) - 1);
      token = strtok(NULL, " ");
    }

    int len = strlen(final_res);
    if (len > 0 && final_res[len - 1] == ' ')
      final_res[len - 1] = '\0';

    strncpy(list[i].command, final_res, MAX_LEN - 1);
  }
}

void wash_data(struct keybind_info *target_list, int count) {
  for (int i = 0; i < count; i++) {
    char tmp[MAX_LEN], *s = target_list[i].description, *d = tmp;
    while (*s && d < tmp + MAX_LEN - 2) {
      if (*s == '"' || *s == '\\')
        *d++ = '\\';
      *d++ = *s++;
    }
    *d = '\0';
    strncpy(target_list[i].description, tmp, MAX_LEN - 1);
  }
}

void print_json(struct Category *group_array, int group_total) {
  puts("[");
  int first_category = 1;

  for (int i = 0; i < group_total; i++) {
    if (group_array[i].count == 0)
      continue;

    if (!first_category)
      puts("  ,");
    first_category = 0;

    puts("  {");
    printf("    \"category\": \"%s\",\n", group_array[i].name);
    puts("    \"keybinds\": [");

    for (int j = 0; j < group_array[i].count; j++) {
      puts("      {");
      printf("        \"key\": \"%s\",\n", group_array[i].list[j].command);
      printf("        \"desc\": \"%s\"\n", group_array[i].list[j].description);
      printf("      }%s\n", (j < group_array[i].count - 1) ? "," : "");
    }
    puts("    ]");
    printf("  }");
  }
  puts("\n]");
}
