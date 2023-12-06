package main

import (
	"encoding/json"
	"fmt"
	"github.com/PuerkitoBio/goquery"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

type Location struct {
	StoreCode              string     `json:"storeCode"`
	BusinessName           string     `json:"businessName"`
	AddressLines           []string   `json:"addressLines"`
	City                   string     `json:"city"`
	State                  string     `json:"state"`
	PostalCode             string     `json:"postalCode"`
	Country                string     `json:"country"`
	Latitude               float64    `json:"latitude"`
	Longitude              float64    `json:"longitude"`
	PhoneNumbers           []string   `json:"phoneNumbers"`
	BusinessHours          [][]string `json:"businessHours"`
	SpecialHours           [][]string `json:"specialHours"`
	FormattedBusinessHours []string   `json:"formattedBusinessHours"`
	Slug                   string     `json:"slug"`
	LocalPageUrl           string     `json:"localPageUrl"`
	Status                 string     `json:"_status"`
	Closed                 bool       `json:"closed"`
}

func whiLocationList(url string) []Location {
	// Make an HTTP GET request
	response, err := http.Get(url)
	if err != nil {
		log.Fatal(err)
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {

		}
	}(response.Body)

	// Check if the status code indicates success
	if response.StatusCode != http.StatusOK {
		log.Fatalf("HTTP request failed with status code: %d", response.StatusCode)
	}

	doc, err := goquery.NewDocumentFromReader(response.Body)
	if err != nil {
		log.Fatal(err)
	}

	var jsonData string

	// Find the script tag with the given ID
	doc.Find("script").Each(func(i int, s *goquery.Selection) {
		if id, exists := s.Attr("id"); exists && id == "__NEXT_DATA__" {
			// Get the text content within the script tag
			text := s.Text()

			// Extract JSON content
			startIndex := strings.Index(text, "{")
			endIndex := strings.LastIndex(text, "}")
			if startIndex != -1 && endIndex != -1 {
				jsonData = text[startIndex : endIndex+1]
			}
		}
	})
	locationData := parseLocationData(jsonData)
	return locationData
}

func parseLocationData(jsonData string) []Location {
	var locationsData struct {
		Props struct {
			PageProps struct {
				Locations []Location `json:"locations"`
			} `json:"pageProps"`
		} `json:"props"`
	}

	err := json.Unmarshal([]byte(jsonData), &locationsData)
	if err != nil {
		log.Fatal(err)
	}

	// Get today's date
	today := time.Now().Format("2006-01-02")

	// Iterate through each location
	for i := range locationsData.Props.PageProps.Locations {
		loc := &locationsData.Props.PageProps.Locations[i]

		// Check if specialHours is not nil and has at least two elements
		if loc.SpecialHours != nil && len(loc.SpecialHours) > 0 && len(loc.SpecialHours[0]) > 1 {
			for _, hours := range loc.SpecialHours {
				if hours[0] == today || hours[1] == today {
					loc.Closed = true
					break
				}
			}
		}
	}

	return locationsData.Props.PageProps.Locations
}

func whiCompute(locations []Location) map[string]float64 {
	statusCounts := make(map[string]int)

	// Count the frequency of different statuses
	for _, loc := range locations {
		status := "Open"
		if loc.Closed == true {
			status = "Closed"
			statusCounts[status]++
		}
		statusCounts[status]++
	}

	// Compute Waffle House Index
	whiIndex := make(map[string]float64)
	totalStores := len(locations)
	for status, count := range statusCounts {
		whiIndex[status] = float64(count) / float64(totalStores)
	}

	return whiIndex
}

func computeColor(index map[string]float64) string {
	if index["Closed"] > 66 {
		return "Red"
	} else if index["Closed"] > 33 {
		return "Yellow"
	} else {
		return "Green"
	}
}

func main() {
	locationList := whiLocationList("https://locations.wafflehouse.com/api/587d236eeb89fb17504336db/locations-details")
	whiIndex := whiCompute(locationList)
	fmt.Println(whiIndex)
	color := computeColor(whiIndex)
	fmt.Println(color)
}
