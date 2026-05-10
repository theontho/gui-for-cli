export interface NavigatorPlatformInfo {
  platform?: string;
  userAgent?: string;
  maxTouchPoints?: number;
  userAgentData?: {
    platform?: string;
  };
}

export function isAppleOperatingSystem(navigatorInfo: NavigatorPlatformInfo = globalThis.navigator) {
  const platform = navigatorInfo.userAgentData?.platform ?? navigatorInfo.platform ?? "";
  const userAgent = navigatorInfo.userAgent ?? "";
  return /Mac|iPhone|iPad|iPod/i.test(platform) || /Macintosh|iPhone|iPad|iPod/i.test(userAgent);
}

export function effectiveWebUIFont(
  preference: string,
  navigatorInfo: NavigatorPlatformInfo = globalThis.navigator
) {
  return preference === "sfPro" || isAppleOperatingSystem(navigatorInfo) ? "sf-pro" : "system";
}
