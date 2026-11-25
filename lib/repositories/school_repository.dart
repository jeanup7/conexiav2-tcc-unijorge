import '../core/api_client.dart';

typedef SchoolData = Map<String, dynamic>;

/// Every operation keeps the API's session guards and server authorization.
class SchoolRepository {
  SchoolRepository(this.api);
  final ApiClient api;
  String base(String child) => '/school/children/${Uri.encodeComponent(child)}';

  Future<List<SchoolData>> items(String path) async =>
      ((await api.request('GET', path))['items'] as List).cast<SchoolData>();

  Future<SchoolData> family(String child) async {
    final values = await Future.wait([
      api.request('GET', '${base(child)}/privacy'),
      items('${base(child)}/tutors'),
      items('${base(child)}/audit'),
    ]);
    return {...values[0] as SchoolData, 'links': values[1], 'audit': values[2]};
  }

  Future<SchoolData> hub() async {
    final values = await Future.wait([
      api.request('GET', '/school/invitations'),
      items('/school/students'),
    ]);
    return {...values[0] as SchoolData, 'students': values[1]};
  }

  Future<List<SchoolData>> candidates() => items('/school/tutor-candidates');
  Future<void> invite(
    String child,
    String tutor,
    String scope,
    String version,
  ) => api.request('POST', '${base(child)}/tutors', {
    'tutorId': tutor,
    'scope': scope,
    'consent': true,
    'consentVersion': version,
  });
  Future<void> privacy(String child, String mode) =>
      api.request('PATCH', '${base(child)}/privacy', {'mode': mode});
  Future<void> revoke(String child, String invitation) => api.request(
    'DELETE',
    '${base(child)}/tutors/${Uri.encodeComponent(invitation)}',
  );
  Future<void> decide(String invitation, bool accept) => api.request(
    'POST',
    '/school/invitations/${Uri.encodeComponent(invitation)}/decision',
    {'accept': accept},
  );
  Future<SchoolData> activity(String child, int days) =>
      api.request('GET', '${base(child)}/activity?days=$days');
}
