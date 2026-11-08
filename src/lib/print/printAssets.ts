/** Wait for print images to either load or fail, but never hold printing open indefinitely. */
export async function waitForPrintImages(root: ParentNode | null = document, timeoutMs = 1500): Promise<void> {
  const images = Array.from(root?.querySelectorAll("img") ?? []);
  if (!images.length) return;

  let timeoutId: number | undefined;
  try {
    await Promise.race([
      Promise.all(images.map((image) => {
        if (image.complete) return Promise.resolve();
        return new Promise<void>((resolve) => {
          const finish = () => resolve();
          image.addEventListener("load", finish, { once: true });
          image.addEventListener("error", finish, { once: true });
          if (image.complete) finish();
        });
      })),
      new Promise<void>((resolve) => {
        timeoutId = window.setTimeout(resolve, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId);
  }
}

/** Popup callers start printing from onload. Let saved logos settle first, with a short cap. */
export function withPrintImageReadiness(html: string): string {
  const script = `<script>(function(){var nativePrint=window.print.bind(window);var queued=false;window.print=function(){if(queued)return;queued=true;var images=Array.prototype.slice.call(document.images);var waits=images.map(function(image){if(image.complete)return Promise.resolve();return new Promise(function(resolve){var done=function(){resolve();};image.addEventListener("load",done,{once:true});image.addEventListener("error",done,{once:true});if(image.complete)done();});});var timer;Promise.race([Promise.all(waits),new Promise(function(resolve){timer=window.setTimeout(resolve,1500);})]).then(function(){window.clearTimeout(timer);queued=false;nativePrint();});};})();</script>`;
  if (/<\/head\s*>/i.test(html)) return html.replace(/<\/head\s*>/i, `${script}</head>`);
  if (/<body(?:\s[^>]*)?>/i.test(html)) return html.replace(/<body(?:\s[^>]*)?>/i, (bodyTag) => `${bodyTag}${script}`);
  return `${script}${html}`;
}
