<?php
// Mautic settings taken from the container's environment. Mautic reads this
// file after config/local.php, which it writes itself, and never writes this
// one, so these settings take precedence.

// Mautic includes this file right after config/local.php, so $parameters holds
// the settings from that file, when it exists.
$parameters ??= [];

$wodbyenv = static function (string $name, ?string $default = null): ?string {
    $value = getenv($name);
    return $value === false || $value === '' ? $default : $value;
};

// The database.
if ($wodbyenv('DB_HOST') !== null) {
    $parameters['db_host'] = $wodbyenv('DB_HOST');
    $parameters['db_port'] = $wodbyenv('DB_PORT', '3306');
    $parameters['db_name'] = $wodbyenv('DB_NAME');
    $parameters['db_user'] = $wodbyenv('DB_USERNAME');
    $parameters['db_password'] = $wodbyenv('DB_PASSWORD', '');
}

// The public address: MAUTIC_SITE_URL, or else WODBY_PRIMARY_URL, the app's
// main route on Wodby. Mautic counts itself installed once its address is
// saved, so the address is only replaced after installation.
$wodbysiteurl = $wodbyenv('MAUTIC_SITE_URL', $wodbyenv('WODBY_PRIMARY_URL'));
if (!empty($parameters['site_url']) && $wodbysiteurl !== null) {
    $parameters['site_url'] = rtrim($wodbysiteurl, '/');
}

// TLS ends at a proxy in front of the container, so the forwarded headers of
// the proxies on private networks are trusted.
$parameters['trusted_proxies'] = array_map('trim', explode(',', $wodbyenv('MAUTIC_TRUSTED_PROXIES', 'PRIVATE_SUBNETS')));

unset($wodbyenv, $wodbysiteurl);
