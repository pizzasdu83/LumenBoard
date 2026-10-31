// LumenBoardHelper: a LaunchDaemon that runs as root, like the helper of Filza.
// When LumenBoard posts the "wipe" notification it deletes what's inside the icon cache folder of iOS, nothing else,
// writes what happened to the result file (the only argument, set in the LaunchDaemon plist) and posts "done".
// The icon cache folder belongs to a system user, the app and SpringBoard (both "mobile") aren't allowed to delete in it.
// Whoever posts the notification can't choose what is deleted or where the result goes.
#include <dispatch/dispatch.h>
#include <errno.h>
#include <ftw.h>
#include <notify.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define LM_FOLDER "/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches"
#define LM_WIPE "com.xsxs18.lumenboard/helper-wipe"
#define LM_DONE "com.xsxs18.lumenboard/helper-done"

static const char *resultPath;
static int found, deleted, failed;
static char firstError[512];

static int visit(const char *path, const struct stat *info, int type, struct FTW *position) {
  if (position->level == 0) return 0; // the folder itself stays
  if (position->level == 1) found++;
  lchflags(path, 0); // an "immutable" flag would stop even root
  if (remove(path) == 0) {
    if (position->level == 1) deleted++;
  } else {
    if (position->level == 1) failed++;
    if (!firstError[0]) snprintf(firstError, sizeof(firstError), "%s: %s", path + position->base, strerror(errno));
  }
  return 0;
}

static void wipe(void) {
  found = deleted = failed = 0;
  firstError[0] = 0;

  // not a real folder (e.g. replaced by a symlink): leave it alone
  struct stat folder;
  if (lstat(LM_FOLDER, &folder) != 0) snprintf(firstError, sizeof(firstError), "%s", strerror(errno));
  else if (!S_ISDIR(folder.st_mode)) snprintf(firstError, sizeof(firstError), "not a folder");
  else nftw(LM_FOLDER, visit, 16, FTW_DEPTH | FTW_PHYS); // children first, symlinks are deleted, never followed

  FILE *file = fopen(resultPath, "w");
  if (file) {
    fprintf(file, "euid=%d\nfound=%d\ndeleted=%d\nfailed=%d\n", (int)geteuid(), found, deleted, failed);
    if (firstError[0]) fprintf(file, "error=%s\n", firstError);
    fclose(file);
    chmod(resultPath, 0644);
  }
  notify_post(LM_DONE);
}

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  resultPath = argv[1];
  static int token;
  notify_register_dispatch(LM_WIPE, &token, dispatch_get_main_queue(), ^(int ignored) {
    wipe();
  });
  dispatch_main();
}
