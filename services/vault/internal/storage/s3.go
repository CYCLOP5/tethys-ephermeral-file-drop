// Package storage wraps the S3 operations Vault needs: presigning PUT and
// GET URLs. The service never reads or writes file bytes itself.
package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Client is a tiny facade over the S3 presigner.
type Client struct {
	S3        *s3.Client
	Presigner *s3.PresignClient
	Bucket    string
}

// NewS3 builds a client using the default AWS credential chain (instance
// profile on EC2, env vars locally).
func NewS3(ctx context.Context, region, bucket string) (*Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("aws config: %w", err)
	}
	client := s3.NewFromConfig(cfg)
	return &Client{
		S3:        client,
		Presigner: s3.NewPresignClient(client),
		Bucket:    bucket,
	}, nil
}

// PresignPut returns a short-lived presigned URL that the browser uses to PUT
// ciphertext directly to S3, bypassing Vault.
func (c *Client) PresignPut(ctx context.Context, key string, size int64, ttl time.Duration) (string, error) {
	out, err := c.Presigner.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(c.Bucket),
		Key:           aws.String(key),
		ContentLength: aws.Int64(size),
	}, func(o *s3.PresignOptions) {
		o.Expires = ttl
	})
	if err != nil {
		return "", err
	}
	return out.URL, nil
}

// PresignGet returns a short-lived presigned URL for the ciphertext.
func (c *Client) PresignGet(ctx context.Context, key string, ttl time.Duration) (string, error) {
	out, err := c.Presigner.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.Bucket),
		Key:    aws.String(key),
	}, func(o *s3.PresignOptions) {
		o.Expires = ttl
	})
	if err != nil {
		return "", err
	}
	return out.URL, nil
}
