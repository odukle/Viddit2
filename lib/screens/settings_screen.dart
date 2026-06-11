import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/reddit_api.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final RedditApi _api = RedditApi();
  bool _nsfwAllowed = false;
  String _selectedGeo = 'AUTO';

  static const Map<String, String> _allCountries = {
    'AF': 'Afghanistan',
    'AX': 'Åland Islands',
    'AL': 'Albania',
    'DZ': 'Algeria',
    'AS': 'American Samoa',
    'AD': 'Andorra',
    'AO': 'Angola',
    'AI': 'Anguilla',
    'AQ': 'Antarctica',
    'AG': 'Antigua and Barbuda',
    'AR': 'Argentina',
    'AM': 'Armenia',
    'AW': 'Aruba',
    'AU': 'Australia',
    'AT': 'Austria',
    'AZ': 'Azerbaijan',
    'BS': 'Bahamas',
    'BH': 'Bahrain',
    'BD': 'Bangladesh',
    'BB': 'Barbados',
    'BY': 'Belarus',
    'BE': 'Belgium',
    'BZ': 'Belize',
    'BJ': 'Benin',
    'BM': 'Bermuda',
    'BT': 'Bhutan',
    'BO': 'Bolivia',
    'BQ': 'Bonaire, Sint Eustatius and Saba',
    'BA': 'Bosnia and Herzegovina',
    'BW': 'Botswana',
    'BV': 'Bouvet Island',
    'BR': 'Brazil',
    'IO': 'British Indian Ocean Territory',
    'BN': 'Brunei Darussalam',
    'BG': 'Bulgaria',
    'BF': 'Burkina Faso',
    'BI': 'Burundi',
    'CV': 'Cabo Verde',
    'KH': 'Cambodia',
    'CM': 'Cameroon',
    'CA': 'Canada',
    'KY': 'Cayman Islands',
    'CF': 'Central African Republic',
    'TD': 'Chad',
    'CL': 'Chile',
    'CN': 'China',
    'CX': 'Christmas Island',
    'CC': 'Cocos (Keeling) Islands',
    'CO': 'Colombia',
    'KM': 'Comoros',
    'CD': 'Congo (Democratic Republic)',
    'CG': 'Congo (Republic)',
    'CK': 'Cook Islands',
    'CR': 'Costa Rica',
    'CI': 'Côte d\'Tvoire',
    'HR': 'Croatia',
    'CU': 'Cuba',
    'CW': 'Curaçao',
    'CY': 'Cyprus',
    'CZ': 'Czechia',
    'DK': 'Denmark',
    'DJ': 'Djibouti',
    'DM': 'Dominica',
    'DO': 'Dominican Republic',
    'EC': 'Ecuador',
    'EG': 'Egypt',
    'SV': 'El Salvador',
    'GQ': 'Equatorial Guinea',
    'ER': 'Eritrea',
    'EE': 'Estonia',
    'SZ': 'Eswatini',
    'ET': 'Ethiopia',
    'FK': 'Falkland Islands',
    'FO': 'Faroe Islands',
    'FJ': 'Fiji',
    'FI': 'Finland',
    'FR': 'France',
    'GF': 'French Guiana',
    'PF': 'French Polynesia',
    'TF': 'French Southern Territories',
    'GA': 'Gabon',
    'GM': 'Gambia',
    'GE': 'Georgia',
    'DE': 'Germany',
    'GH': 'Ghana',
    'GI': 'Gibraltar',
    'GR': 'Greece',
    'GL': 'Greenland',
    'GD': 'Grenada',
    'GP': 'Guadeloupe',
    'GU': 'Guam',
    'GT': 'Guatemala',
    'GG': 'Guernsey',
    'GN': 'Guinea',
    'GW': 'Guinea-Bissau',
    'GY': 'Guyana',
    'HT': 'Haiti',
    'HM': 'Heard Island and McDonald Islands',
    'VA': 'Holy See',
    'HN': 'Honduras',
    'HK': 'Hong Kong',
    'HU': 'Hungary',
    'IS': 'Iceland',
    'IN': 'India',
    'ID': 'Indonesia',
    'IR': 'Iran',
    'IQ': 'Iraq',
    'IE': 'Ireland',
    'IM': 'Isle of Man',
    'IL': 'Israel',
    'IT': 'Italy',
    'JM': 'Jamaica',
    'JP': 'Japan',
    'JE': 'Jersey',
    'JO': 'Jordan',
    'KZ': 'Kazakhstan',
    'KE': 'Kenya',
    'KI': 'Kiribati',
    'KP': 'North Korea',
    'KR': 'South Korea',
    'KW': 'Kuwait',
    'KG': 'Kyrgyzstan',
    'LA': 'Lao People\'s Democratic Republic',
    'LV': 'Latvia',
    'LB': 'Lebanon',
    'LS': 'Lesotho',
    'LR': 'Liberia',
    'LY': 'Libya',
    'LI': 'Liechtenstein',
    'LT': 'Lithuania',
    'LU': 'Luxembourg',
    'MO': 'Macao',
    'MG': 'Madagascar',
    'MW': 'Malawi',
    'MY': 'Malaysia',
    'MV': 'Maldives',
    'ML': 'Mali',
    'MT': 'Malta',
    'MH': 'Marshall Islands',
    'MQ': 'Martinique',
    'MR': 'Mauritania',
    'MU': 'Mauritius',
    'YT': 'Mayotte',
    'MX': 'Mexico',
    'FM': 'Micronesia',
    'MD': 'Moldova',
    'MC': 'Monaco',
    'MN': 'Mongolia',
    'ME': 'Montenegro',
    'MS': 'Montserrat',
    'MA': 'Morocco',
    'MZ': 'Mozambique',
    'MM': 'Myanmar',
    'NA': 'Namibia',
    'NR': 'Nauru',
    'NP': 'Nepal',
    'NL': 'Netherlands',
    'NC': 'New Caledonia',
    'NZ': 'New Zealand',
    'NI': 'Nicaragua',
    'NE': 'Niger',
    'NG': 'Nigeria',
    'NU': 'Niue',
    'NF': 'Norfolk Island',
    'MK': 'North Macedonia',
    'MP': 'Northern Mariana Islands',
    'NO': 'Norway',
    'OM': 'Oman',
    'PK': 'Pakistan',
    'PW': 'Palau',
    'PS': 'Palestine',
    'PA': 'Panama',
    'PG': 'Papua New Guinea',
    'PY': 'Paraguay',
    'PE': 'Peru',
    'PH': 'Philippines',
    'PN': 'Pitcairn',
    'PL': 'Poland',
    'PT': 'Portugal',
    'PR': 'Puerto Rico',
    'QA': 'Qatar',
    'RE': 'Réunion',
    'RO': 'Romania',
    'RU': 'Russia',
    'RW': 'Rwanda',
    'BL': 'Saint Barthélemy',
    'SH': 'Saint Helena',
    'KN': 'Saint Kitts and Nevis',
    'LC': 'Saint Lucia',
    'MF': 'Saint Martin',
    'PM': 'Saint Pierre and Miquelon',
    'VC': 'Saint Vincent and the Grenadines',
    'WS': 'Samoa',
    'SM': 'San Marino',
    'ST': 'Sao Tome and Principe',
    'SA': 'Saudi Arabia',
    'SN': 'Senegal',
    'RS': 'Serbia',
    'SC': 'Seychelles',
    'SL': 'Sierra Leone',
    'SG': 'Singapore',
    'SX': 'Sint Maarten',
    'SK': 'Slovakia',
    'SI': 'Slovenia',
    'SB': 'Solomon Islands',
    'SO': 'Somalia',
    'ZA': 'South Africa',
    'GS': 'South Georgia and the South Sandwich Islands',
    'SS': 'South Sudan',
    'ES': 'Spain',
    'LK': 'Sri Lanka',
    'SD': 'Sudan',
    'SR': 'Suriname',
    'SJ': 'Svalbard and Jan Mayen',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'SY': 'Syrian Arab Republic',
    'TW': 'Taiwan',
    'TJ': 'Tajikistan',
    'TZ': 'Tanzania',
    'TH': 'Thailand',
    'TL': 'Timor-Leste',
    'TG': 'Togo',
    'TK': 'Tokelau',
    'TO': 'Tonga',
    'TT': 'Trinidad and Tobago',
    'TN': 'Tunisia',
    'TR': 'Turkey',
    'TM': 'Turkmenistan',
    'TC': 'Turks and Caicos Islands',
    'TV': 'Tuvalu',
    'UG': 'Uganda',
    'UA': 'Ukraine',
    'AE': 'United Arab Emirates',
    'GB': 'United Kingdom',
    'UM': 'United States Minor Outlying Islands',
    'US': 'United States',
    'UY': 'Uruguay',
    'UZ': 'Uzbekistan',
    'VU': 'Vanuatu',
    'VE': 'Venezuela',
    'VN': 'Vietnam',
    'VG': 'Virgin Islands (British)',
    'VI': 'Virgin Islands (U.S.)',
    'WF': 'Wallis and Futuna',
    'EH': 'Western Sahara',
    'YE': 'Yemen',
    'ZM': 'Zambia',
    'ZW': 'Zimbabwe',
  };

  String _getAutoDetectLabel() {
    final code = _api.detectedCountryCode ??
        ui.PlatformDispatcher.instance.locale.countryCode;
    if (code == null || code.isEmpty) {
      return 'Auto Detect';
    }
    final upperCode = code.toUpperCase();
    final countryName = _allCountries[upperCode] ?? upperCode;
    return 'Auto Detect ($countryName)';
  }

  String _getSelectedGeoLabel() {
    if (_selectedGeo == 'AUTO') {
      final code = _api.detectedCountryCode ??
          ui.PlatformDispatcher.instance.locale.countryCode;
      if (code == null || code.isEmpty) {
        return 'Auto Detect';
      }
      final name = _allCountries[code.toUpperCase()] ?? code.toUpperCase();
      return 'Auto ($name)';
    }
    if (_selectedGeo == 'GLOBAL') {
      return 'Global';
    }
    return _allCountries[_selectedGeo.toUpperCase()] ?? _selectedGeo;
  }

  void _showRegionSelectionBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _RegionSelectorBottomSheet(
          initialValue: _selectedGeo,
          allCountries: _allCountries,
          autoDetectLabel: _getAutoDetectLabel(),
          onSelected: (val) {
            _saveGeoPreference(val);
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nsfwAllowed = prefs.getBool('NSFW') ?? false;
        _selectedGeo = prefs.getString('geolocation') ?? 'AUTO';
      });
    }
  }

  Future<void> _saveGeoPreference(String value) async {
    await _api.setGeolocation(value);
    if (mounted) {
      setState(() {
        _selectedGeo = value;
      });
    }
  }

  Future<void> _saveNsfwPreference(bool value) async {
    if (!_api.isLoggedIn) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sign In Required',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Please sign in to your Reddit account to customize feed content settings.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK',
                  style: TextStyle(color: AppTheme.accentOrange)),
            ),
          ],
        ),
      );
      return;
    }

    if (value) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Age Verification Required',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You must be 18 years of age or older to view NSFW content. Do you confirm that you are at least 18?',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('NSFW', true);
                await _api.setNsfwAllowed(true);
                setState(() {
                  _nsfwAllowed = true;
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentOrange),
              child: const Text('Confirm (18+)',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('NSFW', false);
      await _api.setNsfwAllowed(false);
      setState(() {
        _nsfwAllowed = false;
      });
    }
  }

  void _unblockUser(String username) async {
    await _api.unblockUserLocal(username);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unblocked u/$username'),
          backgroundColor: AppTheme.surfaceLight,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _unblockSubreddit(String subName) async {
    await _api.unblockSubredditLocal(subName);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unblocked r/$subName'),
          backgroundColor: AppTheme.surfaceLight,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockedUsers = _api.blockedUsersList.toList();
    final blockedSubs = _api.blockedSubredditsList.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: PressableScale(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── FEED CONFIGURATION ───
            _buildSectionHeader(context, 'FEED CONFIGURATION'),
            const SizedBox(height: 12),
            Container(
              decoration: AppTheme.cardDecoration(),
              child: PressableScale(
                onTap: _showRegionSelectionBottomSheet,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: const Icon(Icons.public_rounded,
                        color: AppTheme.accentOrange, size: 20),
                  ),
                  title: Text('Popular Feed Region',
                      style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text('Customize trending content location',
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getSelectedGeoLabel(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.accentOrange,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ─── BLOCKED USERS SECTION ───
            _buildSectionHeader(
                context, 'BLOCKED USERS (${blockedUsers.length})'),
            const SizedBox(height: 12),
            Container(
              decoration: AppTheme.cardDecoration(),
              child: blockedUsers.isEmpty
                  ? _buildEmptyState(
                      Icons.person_off_rounded,
                      'No blocked users',
                      'Users you block from comments or post feeds will appear here.',
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: blockedUsers.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: AppTheme.glassBorder,
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final username = blockedUsers[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.surfaceLight,
                            radius: 16,
                            child: Icon(Icons.person_rounded,
                                color: AppTheme.textSecondary, size: 18),
                          ),
                          title: Text('u/$username',
                              style: Theme.of(context).textTheme.titleSmall),
                          trailing: PressableScale(
                            onTap: () => _unblockUser(username),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accentOrange
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusSm),
                                border: Border.all(
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.3),
                                    width: 0.5),
                              ),
                              child: const Text(
                                'Unblock',
                                style: TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 28),

            // ─── BLOCKED SUBREDDITS SECTION ───
            _buildSectionHeader(
                context, 'BLOCKED SUBREDDITS (${blockedSubs.length})'),
            const SizedBox(height: 12),
            Container(
              decoration: AppTheme.cardDecoration(),
              child: blockedSubs.isEmpty
                  ? _buildEmptyState(
                      Icons.block_rounded,
                      'No blocked subreddits',
                      'Subreddits you block from feeds will appear here.',
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: blockedSubs.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: AppTheme.glassBorder,
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final subName = blockedSubs[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.surfaceLight,
                            radius: 16,
                            child: Icon(Icons.reddit_rounded,
                                color: AppTheme.textSecondary, size: 18),
                          ),
                          title: Text('r/$subName',
                              style: Theme.of(context).textTheme.titleSmall),
                          trailing: PressableScale(
                            onTap: () => _unblockSubreddit(subName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.accentOrange
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusSm),
                                border: Border.all(
                                    color: AppTheme.accentOrange
                                        .withValues(alpha: 0.3),
                                    width: 0.5),
                              ),
                              child: const Text(
                                'Unblock',
                                style: TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 28),

            // ─── CONTENT SAFETY SECTION ───
            _buildSectionHeader(context, 'CONTENT SAFETY'),
            const SizedBox(height: 12),
            Container(
              decoration: AppTheme.cardDecoration(),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 20),
                ),
                title: Text('NSFW Content',
                    style: Theme.of(context).textTheme.titleSmall),
                subtitle: Text('Allow adult content in feeds',
                    style: Theme.of(context).textTheme.bodySmall),
                trailing: Switch(
                  value: _nsfwAllowed,
                  activeThumbColor: AppTheme.accentOrange,
                  onChanged: _saveNsfwPreference,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionSelectorBottomSheet extends StatefulWidget {
  final String initialValue;
  final Map<String, String> allCountries;
  final String autoDetectLabel;
  final ValueChanged<String> onSelected;

  const _RegionSelectorBottomSheet({
    required this.initialValue,
    required this.allCountries,
    required this.autoDetectLabel,
    required this.onSelected,
  });

  @override
  State<_RegionSelectorBottomSheet> createState() =>
      __RegionSelectorBottomSheetState();
}

class __RegionSelectorBottomSheetState
    extends State<_RegionSelectorBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<MapEntry<String, String>> _sortedCountries;

  @override
  void initState() {
    super.initState();
    _sortedCountries = widget.allCountries.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCountries = _sortedCountries.where((entry) {
      final query = _searchQuery.toLowerCase();
      final name = entry.value.toLowerCase();
      final code = entry.key.toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();

    final showAutoDetect = _searchQuery.isEmpty ||
        widget.autoDetectLabel
            .toLowerCase()
            .contains(_searchQuery.toLowerCase()) ||
        'auto'.contains(_searchQuery.toLowerCase());

    final showGlobal =
        _searchQuery.isEmpty || 'global'.contains(_searchQuery.toLowerCase());

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        border: Border(
          top: BorderSide(color: AppTheme.glassBorder, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Feed Region',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                PressableScale(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppTheme.glassBorder, width: 0.5),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.glassBorder, width: 0.5),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: AppTheme.accentOrange,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Search regions...',
                  hintStyle: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.textSecondary, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppTheme.textSecondary, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (showAutoDetect) ...[
                  _buildItem(
                    context: context,
                    value: 'AUTO',
                    label: widget.autoDetectLabel,
                    isSelected: widget.initialValue == 'AUTO',
                  ),
                  const Divider(color: AppTheme.glassBorder, height: 1),
                ],
                if (showGlobal) ...[
                  _buildItem(
                    context: context,
                    value: 'GLOBAL',
                    label: 'Global',
                    isSelected: widget.initialValue == 'GLOBAL',
                  ),
                  const Divider(color: AppTheme.glassBorder, height: 1),
                ],
                ...filteredCountries.map((entry) {
                  return _buildItem(
                    context: context,
                    value: entry.key,
                    label: entry.value,
                    isSelected: widget.initialValue == entry.key,
                  );
                }),
                if (!showAutoDetect && !showGlobal && filteredCountries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.5),
                            size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'No regions found',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Try searching for a different country name or code',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required String value,
    required String label,
    required bool isSelected,
  }) {
    return PressableScale(
      onTap: () {
        widget.onSelected(value);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: AppTheme.accentOrange,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
