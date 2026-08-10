const getFriendlyNotifTimeString = (timestamp) => {
    if (!timestamp) return '';
    const messageTime = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - messageTime.getTime();

    // Less than 1 minute
    if (diffMs < 60000)
        return 'Now';

    // Same day - show relative time
    if (messageTime.toDateString() === now.toDateString()) {
        const diffMinutes = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);

        if (diffHours > 0) {
            return `${diffHours}h`;
        } else {
            return `${diffMinutes}m`;
        }
    }

    // Multiple days - show relative days
    const diffDays = Math.floor(diffMs / 86400000);
    if (diffDays > 0) {
        return `${diffDays}d`;
    }

    // Yesterday (fallback, shouldn't reach here normally)
    if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
        return 'Yesterday';

    // Older dates (fallback for very old notifications)
    return Qt.formatDateTime(messageTime, "MMMM dd");
};

const processNotificationBody = (body, appName) => {
    if (!body)
        return "";

    let processedBody = body;

    // Limpiar notificaciones de navegadores basados en Chromium
    if (appName) {
        const lowerApp = appName.toLowerCase();
        const chromiumBrowsers = ["brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"];

        if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
            const lines = body.split('\n\n');

            if (lines.length > 1 && lines[0].startsWith('<a')) {
                processedBody = lines.slice(1).join('\n\n');
            }
        }
    }

    // No reemplazar saltos de línea con espacios
    return processedBody;
};

// Sanitize a notification body for safe rich-text (HTML) rendering.
// Escapes everything, then re-allows only a small whitelist of tags so
// <b> / <i> / <u> / <br> format properly while literal <, >, & and
// arbitrary HTML (images, links, etc.) are neutralized.
const sanitizeBody = (body, appName) => {
    const stripped = processNotificationBody(body, appName);
    if (!stripped)
        return "";

    let escaped = stripped
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");

    // Restore whitelisted inline tags
    escaped = escaped
        .replace(/&lt;b&gt;/gi, "<b>")
        .replace(/&lt;\/b&gt;/gi, "</b>")
        .replace(/&lt;i&gt;/gi, "<i>")
        .replace(/&lt;\/i&gt;/gi, "</i>")
        .replace(/&lt;u&gt;/gi, "<u>")
        .replace(/&lt;\/u&gt;/gi, "</u>")
        // <br>, <br/>, <br />, <br/>
        .replace(/&lt;br\s*\/?&gt;/gi, "<br/>");

    return escaped;
};