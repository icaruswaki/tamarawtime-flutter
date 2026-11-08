"""Synthetic fixtures only; no licensed GTFS is redistributed."""
import csv
import tempfile
import unittest
from pathlib import Path

from import_gtfs import import_feed


class ImportGtfsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.feed = Path(self.temp.name)
        self.write('routes.txt', ['route_id', 'route_short_name', 'route_type'], [
            ['r1', 'Fixture BUS', '3'], ['r2', 'Second', '3']])
        self.write('trips.txt', ['trip_id', 'route_id'], [
            ['first', 'r1'], ['later', 'r1'], ['other', 'r2']])
        self.write('stops.txt', ['stop_id', 'stop_name', 'stop_lat', 'stop_lon'], [
            ['s1', 'First, quoted', '14.6', '121'],
            ['s2', 'Second', '14.61', '121.01'],
            ['invalid', 'Bad position', 'nan', '121']])
        self.write('stop_times.txt', ['trip_id', 'stop_id', 'stop_sequence', 'arrival_time'], [
            ['first', 's2', '2', '08:02:00'], ['first', 's1', '1', '08:01:00'],
            ['first', 'invalid', '3', '08:03:00'], ['first', 's2', 'bad', '08:04:00'],
            ['first', 's2', '-1', '08:00:00'], ['later', 's2', '1', '09:00:00']])

    def write(self, filename, headers, records):
        with (self.feed / filename).open('w', encoding='utf-8-sig', newline='') as file:
            writer = csv.writer(file)
            writer.writerow(headers)
            writer.writerows(records)

    def test_first_trip_is_sorted_not_concatenated(self):
        result = import_feed(self.feed, 250)
        self.assertEqual(result['route_stops']['r1'], ['s1', 's2'])
        self.assertEqual(result['stops'][0]['name'], 'First, quoted')
        self.assertEqual(len(result['stops']), 2)

    def test_historical_status_and_provenance_survive_import(self):
        result = import_feed(self.feed, 1, source='Synthetic fixture v1',
                             license_reference='Synthetic test records')
        self.assertEqual(result['data_status'], 'unverified_historical')
        self.assertTrue(all(route['historical'] for route in result['routes']))
        self.assertEqual(result['source'], 'Synthetic fixture v1')
        self.assertEqual(result['license_reference'], 'Synthetic test records')
        self.assertNotIn('arrival_time', str(result))
        self.assertNotIn('fare', result)
        self.assertEqual(len(result['routes']), 1)

    def test_zero_includes_all_routes_negative_is_rejected(self):
        self.assertEqual(len(import_feed(self.feed, 0)['routes']), 2)
        with self.assertRaises(ValueError):
            import_feed(self.feed, -1)

    def test_missing_required_files_are_reported(self):
        (self.feed / 'stop_times.txt').unlink()
        with self.assertRaisesRegex(ValueError, 'stop_times.txt'):
            import_feed(self.feed, 1)


if __name__ == '__main__':
    unittest.main()
