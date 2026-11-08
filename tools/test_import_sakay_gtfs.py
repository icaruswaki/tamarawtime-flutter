"""Tests use self-authored CSV fixtures; no network or third-party data needed."""
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from import_sakay_gtfs import convert, compact_catalog


class SakayImporterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.feed = self.root / 'feed'
        self.feed.mkdir()
        self.files = {
            'routes.txt': 'route_id,route_long_name,route_type\nLTFRB_PUJ100,Sample - Market,3\nr2,Unknown road service,3\nr3,Rail fixture,2\n',
            'stops.txt': 'stop_id,stop_name,stop_lat,stop_lon\n1,Terminal,14.6,121\n2,Market,14.61,121.01\n3,Bad position,nan,300\n',
            'trips.txt': 'trip_id,route_id\nt1,LTFRB_PUJ100\nt2,LTFRB_PUJ100\nt3,r2\n',
            'stop_times.txt': 'trip_id,stop_id,stop_sequence,arrival_time\nt1,2,2,08:00:00\nt1,1,1,08:01:00\nt1,3,3,08:02:00\nt1,1,bad,08:03:00\nt1,1,-1,08:04:00\nt1,missing,4,08:05:00\nt2,2,1,09:00:00\n',
        }
        for name, content in self.files.items():
            (self.feed / name).write_text(content, encoding='utf-8-sig')

    def test_original_kit_sample_and_first_trip_order(self):
        result = convert(self.feed)
        route = result['routes'][0]
        self.assertTrue(route['historical_only'])
        self.assertFalse(route['validated_current_operation'])
        self.assertEqual(route['mode'], 'jeepney_reference')
        self.assertEqual([s['name'] for s in route['ordered_stops_from_one_sample_trip']],
                         ['Terminal', 'Market', 'Bad position'])
        self.assertNotIn('arrival_time', json.dumps(result))

    def test_invalid_coordinates_remain_unknown_without_dropping_named_stops(self):
        stop = convert(self.feed)['routes'][0]['ordered_stops_from_one_sample_trip'][-1]
        self.assertIsNone(stop['lat'])
        self.assertIsNone(stop['lon'])
        self.assertEqual(stop['coordinate_status'], 'historical_unreviewed')
        json.dumps(convert(self.feed), allow_nan=False)

    def test_type_three_does_not_claim_bus_or_verified_jeepney(self):
        result = convert(self.feed)
        self.assertEqual(result['routes'][1]['mode'], 'road_transit_unclassified')
        self.assertEqual(result['routes'][2]['mode'], 'rail_reference')
        self.assertEqual(result['routes'][2]['ordered_stops_from_one_sample_trip'], [])

    def test_zip_and_directory_have_same_routes_with_license_provenance(self):
        archive = self.root / 'feed.zip'
        with zipfile.ZipFile(archive, 'w') as file:
            for name, content in self.files.items():
                file.writestr('nested/' + name, content)
        result = convert(archive)
        self.assertEqual(result['routes'], convert(self.feed)['routes'])
        self.assertEqual(len(result['provenance']['archive_sha256']), 64)
        self.assertIn('LICENSE', result['license_url'])

    def test_ambiguous_archive_and_missing_files_fail_closed(self):
        archive = self.root / 'ambiguous.zip'
        with zipfile.ZipFile(archive, 'w') as file:
            file.writestr('one/routes.txt', self.files['routes.txt'])
            file.writestr('two/routes.txt', self.files['routes.txt'])
        with self.assertRaisesRegex(ValueError, 'Ambiguous'):
            convert(archive)
        (self.feed / 'routes.txt').unlink()
        with self.assertRaisesRegex(ValueError, 'requires'):
            convert(self.feed)

    def test_cli_requires_license_acknowledgement_before_writing(self):
        output = self.root / 'output.json'
        result = subprocess.run([sys.executable, '-B', str(Path(__file__).with_name('import_sakay_gtfs.py')),
                                 '--input', str(self.feed), '--output', str(output)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_compact_output_preserves_sample_sequence_and_named_stop_dictionary(self):
        original = convert(self.feed)
        compact = compact_catalog(original)
        self.assertEqual(compact['schema_version'], 2)
        route = compact['routes'][0]
        restored = [{**compact['stops'][visit['stop_id']], **visit}
                    for visit in route['ordered_stops_from_one_sample_trip']]
        self.assertEqual(restored, original['routes'][0]['ordered_stops_from_one_sample_trip'])
        self.assertNotIn('name', route['ordered_stops_from_one_sample_trip'][0])


if __name__ == '__main__':
    unittest.main()
