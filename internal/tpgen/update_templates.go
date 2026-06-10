package tpgen

import "fmt"

func ChooseUpdateTemplate(templates []Template, seed int) (Template, error) {
	if len(templates) == 0 {
		return Template{}, fmt.Errorf("no templates available")
	}
	if seed < 0 {
		seed = -seed
	}
	index := seed % len(templates)
	return templates[index], nil
}
