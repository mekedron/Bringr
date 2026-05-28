#import <ApplicationServices/ApplicationServices.h>

int BringrSetFrontProcess(pid_t pid) {
    ProcessSerialNumber process;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus getStatus = GetProcessForPID(pid, &process);
    if (getStatus != noErr) { return 0; }

    OSStatus frontStatus = SetFrontProcessWithOptions(
        &process, kSetFrontProcessFrontWindowOnly
    );
#pragma clang diagnostic pop

    return frontStatus == noErr ? 1 : 0;
}
